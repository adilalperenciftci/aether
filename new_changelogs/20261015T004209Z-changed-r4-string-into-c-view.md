- **A string stored through a C memory view is its characters.** A
  `string[]` view of a `ptr` (`(names as string[])[0] = "VK_KHR_..."`) is
  C's memory, read as a `const char**`: a string stored through it is now
  its characters, as at every other C boundary (R4), where it was the
  string as Aether holds it. Vulkan's extension name arrays are built
  this way.
