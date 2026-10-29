- **The cross-version ABI matrix accepts matching shared runtimes.** CI
  can compare a tree with its own published release. The matrix now reads
  the libraries' runtime ABI IDs and verifies successful calls and imports
  when they match, while still requiring rejection when they differ.
