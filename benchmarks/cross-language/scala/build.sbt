name := "scala-benchmark"
version := "1.0"
scalaVersion := "2.13.12"

// No third-party dependencies: the suite compares standard libraries.

// The runtime classpath (the compiled classes and the Scala library), written
// to classpath.txt for the runner, which starts each benchmark with `java -cp`
// like the Java column. Written by sbt itself, not scraped from what it
// prints: on CI sbt ended its output with a terminal escape (ESC[0J) and no
// newline, so the last line of `export Runtime / fullClasspath` was that
// escape, and every run failed with its class not found.
lazy val writeClasspath = taskKey[Unit]("Writes the runtime classpath to classpath.txt")

writeClasspath := {
  val cp = (Runtime / fullClasspath).value.map(_.data.getAbsolutePath)
  IO.write(baseDirectory.value / "classpath.txt", cp.mkString(java.io.File.pathSeparator))
}
