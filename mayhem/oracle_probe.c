/* Oracle helper: prints what the faked clocks report; run under LD_PRELOAD=src/libfaketime.so.1. */
#include <stdio.h>
#include <sys/time.h>
#include <time.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
  int i, n = argc > 1 ? atoi(argv[1]) : 1;
  for (i = 0; i < n; i++)
  {
    struct timespec ts;
    struct timeval tv;
    time_t t = time(NULL);
    clock_gettime(CLOCK_REALTIME, &ts);
    gettimeofday(&tv, NULL);
    printf("time=%lld clock=%lld.%09ld tv=%lld.%06ld\n", (long long)t, (long long)ts.tv_sec, ts.tv_nsec,
           (long long)tv.tv_sec, (long)tv.tv_usec);
  }
  return 0;
}
