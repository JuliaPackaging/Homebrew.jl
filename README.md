Homebrew.jl (OSX only)
======================

Homebrew.jl sets up a [homebrew](http://brew.sh) installation inside your [Julia](http://julialang.org/) package directory.  It uses Homebrew to provide specialized binary packages to satisfy dependencies for other Julia packages, without the need for a compiler or other development tools; it is completely self-sufficient.

Package authors with dependencies that want binaries distributed in this manner should open an issue here.  A [Homebrew formula](https://github.com/mxcl/homebrew/tree/master/Library/Formula) for the dependency you wish to provide will help speed along the process.

Usage (Users)
=============

As a user, you ideally shouldn't ever have to use Homebrew directly, short of installing it.  However, in an effort to be realistic, there is a simple to use interface for interacting with the Homebrew package manager:

* `Homebrew.add("pkg")` will install `pkg`
* `Homebrew.rm("pkg")` will uninstall `pkg`
* `Homebrew.update()` will update the available formulae for installation.
* `Homebrew.list("pkg")` will list all installed packaages and versions
* `Homebrew.installed("pkg")` will return a boolean denoting whether or not `pkg` is installed
* `Homebrew.prefix()` will return the prefix that all packages are installed to


Usage (Package Authors)
=======================

As a package author, to use Homebrew.jl you use the `Homebrew.HB` provider and pass the formula name in via BinDeps' `provides()` function:

```julia
libffi = library_dependency("ffi", aliases = ["libffi"], runtime = false)

...

using Homebrew
provides( Homebrew.HB, "libffi", libffi, os = :Darwin )
```

Then, the `Homebrew` package will automatically download the requisite bottles for any dependencies you state it can provide.

