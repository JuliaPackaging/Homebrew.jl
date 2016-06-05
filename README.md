# Homebrew.jl (OSX only)

[![Build Status](https://travis-ci.org/JuliaLang/Homebrew.jl.svg)](https://travis-ci.org/JuliaLang/Homebrew.jl)

Homebrew.jl sets up a [homebrew](http://brew.sh) installation inside your [Julia](http://julialang.org/) package directory.  It uses Homebrew to provide specialized binary packages to satisfy dependencies for other Julia packages, without the need for a compiler or other development tools; it is completely self-sufficient.

Package authors with dependencies that want binaries distributed in this manner should open an issue here for inclusion into the package database.

NOTE: If you have MacPorts installed, and are seeing issues with `git` or `curl` complaining about certificates, try to update the the ```curl``` and ```curl-ca-bundle``` packages before using Homebrew.jl. From the terminal, run:
```
port selfupdate
port upgrade curl curl-ca-bundle
```

Usage (Users)
=============

As a user, you ideally shouldn't ever have to use Homebrew directly, short of installing it.  However, in an effort to be realistic, there is a simple to use interface for interacting with the Homebrew package manager:

* `Homebrew.add("pkg")` will install `pkg`, note that if you want to install a package from a non-default tap, you can do so via `Homebrew.add("user/tap/formula")`.  An example of this is installing the `metis4` formula from the [`Homebrew/science` tap](https://github.com/Homebrew/homebrew-science) via `Homebrew.add("homebrew/science/metis4")`.
* `Homebrew.rm("pkg")` will uninstall `pkg`
* `Homebrew.update()` will update the available formulae for installation and upgrade installed packages if a newer version is available
* `Homebrew.list()` will list all installed packages and versions
* `Homebrew.installed("pkg")` will return a boolean denoting whether or not `pkg` is installed
* `Homebrew.prefix()` will return the prefix that all packages are installed to


Usage (Package Authors)
=======================

As a package author, the first thing to do is to [write](https://github.com/mxcl/homebrew/wiki/Formula-Cookbook)/[find](https://github.com/mxcl/homebrew/tree/master/Library/Formula) a homebrew formula for whatever package you wish to create.  Once you have verified that is working, (and it works with your Julia package) open an issue here for your formula to be included in the library of formulae provided by `Homebrew.jl`.  To see examples of formulae that are already accepted, peruse the [homebrew-juliadeps](https://github.com/staticfloat/homebrew-juliadeps) repository.

To have your Julia package automatically install these precompiled binaries, `Homebrew.jl` offers a BinDeps provider which can be accessed as `Homebrew.HB`.  Simply declare your dependency on `Homebrew.jl` via a `@osx Homebrew` in your REQUIRE files, create a BinDeps `library_dependency` and state that `Homebrew` provides that dependency:

```julia
using BinDeps
@BinDeps.setup
nettle = library_dependency("nettle", aliases = ["libnettle","libnettle-4-6"])

...

using Homebrew
provides( Homebrew.HB, "nettle", nettle, os = :Darwin )
```

Then, the `Homebrew` package will automatically download the requisite bottles for any dependencies you state it can provide.


Why Package Authors should use Homebrew.jl
------------------------------------------
A common question is why bother with Homebrew formulae and such when a package author could simply compile the `.dylib`'s needed by their package, upload them somewhere and download them to a user's installation somewhere.  There are multiple reasons, and although they are individually surmountable Homebrew offers a simpler (and standardized) method of solving many of these problems automatically:

* On OSX shared libraries link via full paths.  This means that unless you manually alter the path inside of a `.dylib` or binary to have an `@rpath` or `@executable_path` in it, the path will be attempting to point to the exact location on your harddrive that the shared library was found at compile-time.  This is not an issue if all libraries linked to are standard system libraries, however as soon as you wish to link to a library in a non-standard location you must alter the paths.  Homebrew does this for you automatically, rewriting the paths during installation via `install_name_tool`.  To see the paths embedded in your libraries and executable files, run `otool -L <file>`.

* Dependencies on other libraries are handled gracefully by Homebrew.  If your package requires some heavy-weight library such as `cairo`, `glib`, etc... Homebrew already has those libraries ready to be built for you.  Just add a `depends_on` line into your Homebrew formula, and you're ready to go.

* Releasing new versions of binaries can be difficult.  Homebrew.jl has builtin mechanisms for upgrading all old packages, and even detecting when a binary of the same version number has a new revision (e.g. if an old binary had an error embedded inside it).  The Julia build process itself often falls prey to this exact problem when newer versions of dependencies come out (whether with version number bumps or no).

