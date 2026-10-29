- **`hide` and `seal except` now cover DSL receiver fallback.** A trailing
  builder block could previously resolve a blocked bare name through its
  receiver-prefixed method before lexical visibility was enforced.
