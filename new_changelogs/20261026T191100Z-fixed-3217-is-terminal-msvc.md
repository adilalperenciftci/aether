- **`io.is_terminal` answers for a descriptor that is not open under
  MSVC.** The CRT's invalid-parameter handler ended an MSVC-built program
  from `_get_osfhandle`; the call now runs with a quiet handler and the
  answer is false (#3217).
