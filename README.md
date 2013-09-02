Homebrew.jl (OSX only)
======================

Homebrew.jl sets up a [homebrew](http://brew.sh) installation inside your [Julia](http://julialang.org/) package directory.  It uses Homebrew to provide specialized binary packages to satisfy dependencies for other Julia packages, without the need for a compiler or other development tools; it is completely self-sufficient.

Package authors with dependencies that want binaries distributed in this manner should open an issue here.  A [Homebrew formula](https://github.com/mxcl/homebrew/tree/master/Library/Formula) for the dependency you wish to provide will help speed along the process.

Usage
=====

As a package author, to use Homebrew.jl you use the `Homebrew.HB` provider and pass the formula name in via BinDeps' `provides()` function:

```julia
libffi = library_dependency("ffi", aliases = ["libffi"], runtime = false)

...

using Homebrew
provides( Homebrew.HB, "libffi", libffi, os = :Darwin )
```

Then, the `Homebrew` package will automatically download the requisite bottles for any dependencies you state it can provide.
