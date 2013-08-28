Homebrew.jl (OSX only)
======================

Homebrew.jl sets up a [homebrew](http://brew.sh) installation inside your [Julia](http://julialang.org/) package directory.  It uses Homebrew to provide specialized binary packages to satisfy dependencies for other Julia packages, without the need for a compiler or other development tools; it is completely self-sufficient.

Package authors with dependencies that want binaries distributed in this manner should open an issue here.  A [Homebrew formula](https://github.com/mxcl/homebrew/tree/master/Library/Formula) for the dependency you wish to provide will help speed along the process.