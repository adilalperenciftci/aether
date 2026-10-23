- **Hoisting a function's branch-bound locals is linear in them.** The
  checker and codegen walked the function body once per name bound in its
  branches (the joins, the written type, the first binding, whether the
  name is read), codegen scanned every declared local per lookup, and the
  unused-variable pass compared every reference with every local. Each
  question now reads what one walk of the body gathered: a generated main
  with 3000 such names compiles in 0.13 s, from 2.57 s, and one with 6000
  in 0.25 s, from 16.17 s. A function also hoisted at most 64 names out of
  its branches, so a 65th, bound in an arm and read after it, was refused
  as "Undefined variable"; any number is hoisted now (#3083).
