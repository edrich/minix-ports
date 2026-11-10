// threads.cpp - libstdc++ thread support over MINIX libmthread (gthreads):
// std::thread/jthread, mutex, condition_variable (incl. timeouts),
// thread_local (emutls: one value per thread), shared_mutex, call_once,
// future/promise/async, this_thread::yield/sleep_for, plus std::format.
// MINIX threads are cooperative: a thread runs until it blocks in, or
// yields through, a threads call.  Prints TC-THREADS-OK or the first
// failed check.
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <format>
#include <future>
#include <mutex>
#include <set>
#include <shared_mutex>
#include <string>
#include <thread>
#include <vector>

using namespace std::chrono_literals;

static int failures;
#define CHECK(c) do { if (!(c)) { std::printf("TC-THREADS-FAIL line %d: %s\n", \
	__LINE__, #c); failures++; } } while (0)

static thread_local int tls_value = 7;

int main()
{
	// Threads, ids, mutex, yield.
	std::mutex m;
	int counter = 0;
	std::set<std::thread::id> ids;
	std::vector<std::thread> ts;
	CHECK(std::this_thread::get_id() != std::thread::id());
	for (int i = 0; i < 4; i++)
		ts.emplace_back([&, i] {
			tls_value = 100 + i;
			for (int k = 0; k < 50; k++) {
				std::lock_guard<std::mutex> g(m);
				counter++;
				if (k == 0)
					ids.insert(std::this_thread::get_id());
			}
			std::this_thread::yield();
			CHECK(tls_value == 100 + i);
		});
	for (auto &t : ts) {
		CHECK(t.joinable());
		CHECK(t.get_id() != std::thread::id());
		t.join();
	}
	CHECK(counter == 200);
	CHECK(ids.size() == 4);
	CHECK(ids.count(std::this_thread::get_id()) == 0);
	CHECK(tls_value == 7);	// main thread's copy untouched

	// condition_variable: producer/consumer, then a timeout.
	std::condition_variable cv;
	std::vector<int> queue;
	bool done = false;
	int consumed = 0;
	std::thread consumer([&] {
		std::unique_lock<std::mutex> lk(m);
		for (;;) {
			cv.wait(lk, [&] { return !queue.empty() || done; });
			while (!queue.empty()) {
				consumed += queue.back();
				queue.pop_back();
			}
			if (done)
				break;
		}
	});
	for (int i = 1; i <= 10; i++) {
		{ std::lock_guard<std::mutex> g(m); queue.push_back(i); }
		cv.notify_one();
		std::this_thread::yield();
	}
	{ std::lock_guard<std::mutex> g(m); done = true; }
	cv.notify_all();
	consumer.join();
	CHECK(consumed == 55);
	{
		std::unique_lock<std::mutex> lk(m);
		auto t0 = std::chrono::steady_clock::now();
		bool r = cv.wait_for(lk, 50ms, [] { return false; });
		auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
		    std::chrono::steady_clock::now() - t0).count();
		CHECK(!r);
		CHECK(ms >= 40 && ms < 3000);
	}

	// shared_mutex (pthread rwlock): shared + exclusive, try variants.
	std::shared_mutex sm;
	sm.lock_shared();
	CHECK(sm.try_lock_shared());
	CHECK(!sm.try_lock());
	sm.unlock_shared();
	sm.unlock_shared();
	CHECK(sm.try_lock());
	CHECK(!sm.try_lock_shared());
	sm.unlock();

	// call_once across threads.
	std::once_flag once;
	std::atomic<int> once_runs{0};
	std::thread o1([&] { std::call_once(once, [&] { once_runs++; }); });
	std::thread o2([&] { std::call_once(once, [&] { once_runs++; }); });
	o1.join();
	o2.join();
	CHECK(once_runs == 1);

	// future/promise/async, exception transport.
	std::promise<int> p;
	std::future<int> f = p.get_future();
	std::thread pt([&] { p.set_value(42); });
	CHECK(f.get() == 42);
	pt.join();
	auto a = std::async(std::launch::async, [] { return std::string("async"); });
	CHECK(a.get() == "async");
	auto ex = std::async(std::launch::async, []() -> int {
		throw std::runtime_error("from-thread"); });
	try {
		ex.get();
		CHECK(false);
	} catch (const std::runtime_error &e) {
		CHECK(std::string(e.what()) == "from-thread");
	}

	// jthread + stop_token (C++20).
	std::atomic<int> spins{0};
	{
		std::jthread jt([&](std::stop_token st) {
			while (!st.stop_requested()) {
				spins++;
				std::this_thread::yield();
			}
		});
		for (int i = 0; i < 3; i++)
			std::this_thread::yield();
	}	// destructor: request_stop() + join()
	CHECK(spins > 0);

	// sleep_for blocks the whole process on MINIX, but must return.
	auto t0 = std::chrono::steady_clock::now();
	std::this_thread::sleep_for(20ms);
	CHECK(std::chrono::steady_clock::now() - t0 >= 15ms);

	std::string s = std::format("{}-{:>3}-{:.2f}", "fmt", 7, 1.5);
	CHECK(s == "fmt-  7-1.50");

	if (failures == 0)
		std::printf("TC-THREADS-OK %d %d\n", counter, consumed);
	return failures != 0;
}
