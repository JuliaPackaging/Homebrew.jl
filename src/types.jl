import Base: ==

"""
`BrewPkg`

A simple type to give us some nice ways of representing our packages to the user

It contains important information such as the `name` of the package, the `tap` it
came from, the `version` of the package and whether it was `translated` or not
"""
struct BrewPkg
    # The name of this particular Brew package
    name::String

    # The tap this brew package comes from ("Homebrew/core" in general)
    tap::String

    # The version of this brew package
    version::String
end

function ==(x::BrewPkg, y::BrewPkg)
    return x.name == y.name && x.tap == y.tap && x.version == y.version
end

"""
`fullname(pkg::BrewPkg)`

Return the fully-qualified name for a package, dropping "Homebrew/core"
"""
function fullname(pkg::BrewPkg)
    if pkg.tap == "Homebrew/core"
        return pkg.name
    end
    return joinpath(pkg.tap,pkg.name)
end

"""
`show(io::IO, b::BrewPkg)`

Writes a `BrewPkg` to `io`, showing tap, name and version number
"""
function show(io::IO, b::BrewPkg)
    write(io, "$(fullname(b)): $(b.version)")
end


"""
`StringOrPkg`

A convenience type accepting either an `AbstractString` or a `BrewPkg`
"""
const StringOrPkg = Union{AbstractString, BrewPkg}
