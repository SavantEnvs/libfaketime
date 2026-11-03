/*
 * File-input harness for libfaketime's own configuration parsers. The library
 * source is compiled into this program (so the sanitizers and coverage see it);
 * the single input file selects one configuration surface via FT_MODE:
 *
 *   1  fuzz_faketime_spec     line-oriented settings -> FAKETIME, FAKETIME_FMT and the
 *                             numeric FAKETIME_* limits (the environment-variable parsers)
 *   2  fuzz_faketimerc        the input IS the timestamp configuration file
 *                             (FAKETIME_TIMESTAMP_FILE / ~/.faketimerc)
 *   3  fuzz_timestamp_load    the input IS a FAKETIME_LOAD_FILE timestamp replay file
 *
 * libfaketime's initialiser exit()s on invalid configuration, which is why this is a
 * one-input-per-process target. The setup runs in an early constructor so the settings are in
 * the environment before libfaketime's own constructor reads them.
 */
#define _GNU_SOURCE
#include "../src/libfaketime.c"

#ifndef FT_MODE
#error "compile with -DFT_MODE=1|2|3"
#endif

#define MAX_INPUT 8192

static const char *const spec_vars[] = {
  "FAKETIME", "FAKETIME_FMT", "FAKETIME_START_AFTER_SECONDS", "FAKETIME_STOP_AFTER_SECONDS",
  "FAKETIME_START_AFTER_NUMCALLS", "FAKETIME_STOP_AFTER_NUMCALLS", "FAKETIME_CACHE_DURATION",
};

static void set_lines(const char *data, size_t len)
{
  static char buf[MAX_INPUT + 1];
  char *p = buf;
  size_t i;

  memcpy(buf, data, len);
  buf[len] = '\0';
  for (i = 0; i < sizeof(spec_vars) / sizeof(spec_vars[0]) && p != NULL; i++)
  {
    char *nl = strchr(p, '\n');
    if (nl != NULL)
      *nl = '\0';
    if (*p != '\0')
      setenv(spec_vars[i], p, 1);
    p = nl ? nl + 1 : NULL;
  }
}

static void harness_setup(int argc, char **argv, char **envp)
{
  (void)envp;
  /* A throwaway $HOME and no shm keep the run self-contained; FAKETIME_* from the caller must not leak in. */
  setenv("HOME", "/nonexistent", 1);
  unsetenv("FAKETIME");
  unsetenv("FAKETIME_TIMESTAMP_FILE");
  unsetenv("FAKETIME_LOAD_FILE");
  unsetenv("FAKETIME_SHARED");
  if (argc < 2)
    return;
#if FT_MODE == 1
  {
    static char data[MAX_INPUT];
    FILE *f = fopen(argv[1], "rb");
    size_t n;
    if (f == NULL)
      return;
    n = fread(data, 1, sizeof(data), f);
    fclose(f);
    setenv("FAKETIME_DISABLE_SHM", "1", 1);
    set_lines(data, n);
  }
#elif FT_MODE == 2
  setenv("FAKETIME_DISABLE_SHM", "1", 1);
  setenv("FAKETIME_TIMESTAMP_FILE", argv[1], 1);
#elif FT_MODE == 3
  setenv("FAKETIME", "x1", 1);
  setenv("FAKETIME_LOAD_FILE", argv[1], 1);
#endif
}

static void __attribute__((constructor(101))) harness_early(int argc, char **argv, char **envp)
{
  harness_setup(argc, argv, envp);
}

int main(int argc, char **argv)
{
  static const clockid_t clocks[] = {
    CLOCK_REALTIME, CLOCK_MONOTONIC, CLOCK_MONOTONIC_RAW, CLOCK_BOOTTIME,
    CLOCK_REALTIME_COARSE, CLOCK_MONOTONIC_COARSE, CLOCK_PROCESS_CPUTIME_ID,
  };
  volatile unsigned long sink = 0;
  struct timespec ts;
  struct timeval tv;
  struct timeb tb;
  struct stat st;
  size_t i;
  int round;

  for (round = 0; round < 4; round++)
  {
    for (i = 0; i < sizeof(clocks) / sizeof(clocks[0]); i++)
    {
      if (clock_gettime(clocks[i], &ts) == 0)
        sink += (unsigned long)ts.tv_sec + (unsigned long)ts.tv_nsec;
    }
    sink += (unsigned long)time(NULL);
    if (gettimeofday(&tv, NULL) == 0)
      sink += (unsigned long)tv.tv_sec + (unsigned long)tv.tv_usec;
    if (timespec_get(&ts, TIME_UTC) != 0)
      sink += (unsigned long)ts.tv_sec;
    ftime(&tb);
    sink += (unsigned long)tb.time + (unsigned long)tb.millitm;
    if (argc > 1 && stat(argv[1], &st) == 0)
      sink += (unsigned long)st.st_mtime;
  }
  (void)sink;
  return 0;
}
