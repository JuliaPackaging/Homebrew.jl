# Homebrew.jl (OSX only)

[![Build Status](https://travis-ci.org/JuliaPackaging/Homebrew.jl.svg)](https://travis-ci.org/JuliaPackaging/Homebrew.jl)

Homebrew.jl sets up a [homebrew](http://brew.sh) installation inside your [Julia](http://julialang.org/) package directory.  It uses Homebrew to provide specialized binary packages to satisfy dependencies for other Julia packages, without the need for a compiler or other development tools; it is completely self-sufficient.

Package authors with dependencies that want binaries distributed in this manner should open an issue here for inclusion into the package database.

NOTE: If you have MacPorts installed, and are seeing issues with `git` or `curl` complaining about certificates, try to update the the ```curl``` and ```curl-ca-bundle``` packages before using Homebrew.jl. From the terminal, run:
```
port selfupdate
port upgrade curl curl-ca-bundle
```

# Usage (Users)

As a user, you ideally shouldn't ever have to use Homebrew directly, short of installing it via `Pkg.add("Homebrew")`. However, there is a simple to use interface for interacting with the Homebrew package manager:

* `Homebrew.add("pkg")` will install `pkg`, note that if you want to install a package from a non-default tap, you can do so via `Homebrew.add("user/tap/formula")`.  An example of this is installing the `metis4` formula from the [`Homebrew/science` tap](https://github.com/Homebrew/homebrew-science) via `Homebrew.add("homebrew/science/metis4")`.
* `Homebrew.rm("pkg")` will uninstall `pkg`
* `Homebrew.update()` will update the available formulae for installation and upgrade installed packages if a newer version is available
* `Homebrew.list()` will list all installed packages and versions
* `Homebrew.installed("pkg")` will return a `Bool` denoting whether or not `pkg` is installed
* `Homebrew.prefix()` will return the prefix that all packages are installed to


# Usage (Package Authors)

As a package author, the first thing to do is to [write](https://github.com/Homebrew/brew/blob/master/share/doc/homebrew/Formula-Cookbook.md)/[find](http://braumeister.org/) a Homebrew formula for whatever package you wish to create.  The easiest way to tell if the binary will work out-of-the-box is `Homebrew.add()` it.  Formulae from the default `homebrew/core` tap need no prefix, but if you are installing something from another tap, you need to prefix it with the appropriate tap name. For example, to install `metis4` from the `homebrew/science` tap, you would run `Homebrew.add("homebrew/science/metis4")`. Programs installed to `<prefix>/bin` and libraries installed to `<prefix>/lib` will automatically be availble for `run()`'ing and `dlopen()`'ing.

If that doesn't "just work", there may be some special considerations necessary for your piece of software. Open an issue here with a link to your formula and we will discuss what the best approach for your software is. To see examples of formulae we have already included for special usage, peruse the [homebrew-juliadeps](https://github.com/staticfloat/homebrew-juliadeps) repository.

To have your Julia package automatically install these precompiled binaries, `Homebrew.jl` offers a BinDeps provider which can be accessed as `Homebrew.HB`.  Simply declare your dependency on `Homebrew.jl` via a `@osx Homebrew` in your REQUIRE files, create a BinDeps `library_dependency` and state that `Homebrew` provides that dependency:

```julia
using BinDeps
@BinDeps.setup
nettle = library_dependency("nettle", aliases = ["libnettle","libnettle-4-6"])

...
# Wrap in @osx_only to avoid non-OSX users from erroring out
@osx_only begin
    using Homebrew
    provides( Homebrew.HB, "nettle", nettle, os = :Darwin )
end

@BinDeps.install Dict(:nettle => :nettle)
```

Then, the `Homebrew` package will automatically download the requisite bottles for any dependencies you state it can provide.  This example garnered from the `build.jl` file from [`Nettle.jl` package](https://github.com/staticfloat/Nettle.jl/blob/master/deps/build.jl).


## Why Package Authors should use Homebrew.jl
A common question is why bother with Homebrew formulae and such when a package author could simply compile the `.dylib`'s needed by their package, upload them somewhere and download them to a user's installation somewhere.  There are multiple reasons, and although they are individually surmountable Homebrew offers a simpler (and standardized) method of solving many of these problems automatically:

* On OSX shared libraries link via full paths.  This means that unless you manually alter the path inside of a `.dylib` or binary to have an `@rpath` or `@executable_path` in it, the path will be attempting to point to the exact location on your harddrive that the shared library was found at compile-time.  This is not an issue if all libraries linked to are standard system libraries, however as soon as you wish to link to a library in a non-standard location you must alter the paths.  Homebrew does this for you automatically, rewriting the paths during installation via `install_name_tool`.  To see the paths embedded in your libraries and executable files, run `otool -L <file>`.

* Dependencies on other libraries are handled gracefully by Homebrew.  If your package requires some heavy-weight library such as `cairo`, `glib`, etc... Homebrew already has those libraries ready to be installed for you.

* Releasing new versions of binaries can be difficult.  Homebrew.jl has builtin mechanisms for upgrading all old packages, and even detecting when a binary of the same version number has a new revision (e.g. if an old binary had an error embedded inside it).



## Why doesn't this package use my system-wide Homebrew installation?

Some of the formulae in the [staticfloat/juliadeps tap](https://github.com/staticfloat/homebrew-juliadeps) are specifically patched to work with Julia. Some of these patches have not (or will not) be merged back into Homebrew mainline, so we don't want to conflict with any packages the user may or may not have installed.

Users can modify Homebrew's internal workings, so it's better to have a known good Homebrew installation than to risk bug reports from users that have unknowingly merged patches into Homebrew that break functionality we require.

If you already have something installed, and it is usable, (e.g. `BinDeps` can load it and it passes any quick internal tests the Package authors have defined) then `Homebrew.jl` won't try to install it. `BinDeps` always checks to see if there is a library in the current load path that satisfies the requirements setup by package authors, and if there is, it doesn't build anything.


## Advanced usage

`Homebrew.jl` provides a convenient wrapper around most of the functionality of Homebrew, however there are rare cases where access to the full suite of `brew` commands is necessary.  To facilitate this, users that are familiar with the `brew` command set can use `Homebrew.brew()` to directly feed commands to the `brew` binary within `Homebrew.jl`.  Example usage:

```
julia> using Homebrew

julia> Homebrew.brew(`info staticfloat/juliadeps/libgfortran`)
staticfloat/juliadeps/libgfortran: stable 6.2 (bottled)
http://gcc.gnu.org/wiki/GFortran
/Users/sabae/.julia/v0.5/Homebrew/deps/usr/Cellar/libgfortran/6.2 (9 files, 2M) *
  Poured from bottle on 2016-11-21 at 13:14:33
From: https://github.com/staticfloat/homebrew-juliadeps/blob/master/libgfortran.rb
==> Dependencies
Build: gcc ✘
```
