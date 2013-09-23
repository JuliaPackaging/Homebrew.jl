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


Why not using system wide Homebrew ?
====================================

We decided not to support this for two reasons:

Some of the formulae in [the used tap](https://github.com/staticfloat/homebrew-juliadeps) are
specifically patched to work with Julia. Some of these patches have not (or will not) be merged
back into Homebrew mainline, so we don't want to conflict with any packages the user
may or may not have installed.

We have modified Homebrew itself to support installation of Formulae without a compiler available.

Users can modify Homebrew's internal workings, it's better to have a known good Homebrew fork than
to risk bug reports from users that have unknowingly merged patches into Homebrew that break
functionality we require

The biggest reason is the patches that have been applied to Homebrew itself.
This package is pretty much meant to serve bottles only;
you should never need to compile anything when using `Homebrew.jl`.
This is on purpose, as there are many users who may wish to install packages for Julia,
but don't have Xcode installed.

If you already have something installed, and it is usable,
(e.g. `BinDeps` can load it and it passes any quick internal tests the Package authors have defined)
then `Homebrew.jl` won't try to install it. `BinDeps` always checks to see if there is a library
in the current load path that satisfies the requirements setup by package authors,
and if there is, it doesn't build anything.

