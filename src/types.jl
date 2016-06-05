"""
BrewPkg

A simple type to give us some nice ways of representing our packages to the user

This object doesn't have too much functionality beyond having `version`, a
`VersionNumber` that is the munged output of `version_str`, due to Homebrew's
versioning being more lax than the SemVer that Julia uses for `VersionNumber`s.
We also track whether this package is bottled, and where its Cellar is.
"""
immutable BrewPkg
    name::String
    version::VersionNumber
    version_str::String
    bottled::Bool
    cellar::String

    BrewPkg(n, v, vs, b) = new(n, v, vs, b)
end


"""
show(io::IO, b::BrewPkg)

Writes a BrewPkg to io, showing its version number and whether it's bottled.
"""
function show(io::IO, b::BrewPkg)
    write(io, "$(b.name): $(b.version_str) $(b.bottled ? "(bottled)" : "")")
end
