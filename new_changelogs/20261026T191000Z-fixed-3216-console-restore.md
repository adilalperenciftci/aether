- **Windows: a program and `ae` leave the console as they found it.** Both
  set the console's code pages to UTF-8, and a program turned on VT
  processing, and left them so after exiting: the shell kept them for every
  later program. They are given back at exit (#3216).
