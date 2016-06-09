"""
BrewPkg

A simple type to give us some nice ways of representing our packages to the user

It contains important information such as the `name` of the package, the `tap` it
came from, the `version` of the package and whether it was `translated` or not
"""
immutable BrewPkg
    # The name of this particular Brew package
    name::String

    # The tap this brew package comes from ("Homebrew/core" in general)
    tap::String

    # The version of this brew package
    version::String

    # Whether this package was translated
    translated::Bool

    # We don't do translation yet, but prepare for it.
    BrewPkg(n, t, v) = new(n, t, v, false)
end


"""
show(io::IO, b::BrewPkg)

Writes a BrewPkg to io, showing its version number and whether it's bottled.
"""
function show(io::IO, b::BrewPkg)
    pkgname = b.name
    if b.tap != "Homebrew/core"
        pkgname = "$(b.tap)/$pkgname"
    end
    write(io, "$pkgname: $(b.version) $(b.translated ? "(translated)" : "")")
end
