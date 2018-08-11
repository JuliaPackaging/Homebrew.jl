"""
`read_formula(pkg::Union{AbstractString,BrewPkg})`

Returns the string contents of a package's formula.
"""
function read_formula(pkg::StringOrPkg) end

function read_formula(name::AbstractString)
    return read(formula_path(name), String)
end

function read_formula(pkg::BrewPkg)
    return read(formula_path(pkg), String)
end

"""
`write_formula(name::AbstractString, formula::AbstractString)`

Write out fully-qualified formula `name` with contents `formula` to disk. Note
that writing out without a tap name is not allowed; we won't write new formulae
out to `Homebrew/core`, only to taps.
"""
function write_formula(name::AbstractString, formula::AbstractString)
    path, tap_path = formula_tap(name)

    if isempty(tap_path)
        error("Cannot write a formula out to Homebrew/core!")
    end

    # Insert the "homebrew-" that exists in all taps
    tap_path = "$(dirname(tap_path))/homebrew-$(basename(tap_path))"

    # Open this file, and write it out!
    path = joinpath(brew_prefix, "Library", "Taps", tap_path, "$path.rb")
    open(path, "w") do f
        write(f, formula)
    end

    # We done!
    return
end


"""
`delete_translated_formula(name::AbstractString; verbose::Bool=false)`

Delete a translated formula from the `staticfloat/juliatranslated` tap.
"""
function delete_translated_formula(name::AbstractString; verbose::Bool=false)
    # Throw out the tap_path part of any formula that someone passed into here.
    path, tap_path = formula_tap(name)

    # Override tap_path with our auto_tapname
    tap_path = "$(dirname(auto_tapname))/homebrew-$(basename(auto_tapname))"

    try
        del_path = joinpath(brew_prefix, "Library", "Taps", tap_path, "$path.rb")
        Base.rm(del_path)
        if verbose
            println("Deleting $(basename(del_path))...")
        end
    catch
    end
end

"""
`delete_all_translated_formulae(;verbose::Bool=false)`

Delete all translated formulae from the `staticfloat/juliatranslated` tap. This
is useful for debugging misbehaving formulae during translation.
"""
function delete_all_translated_formulae(;verbose::Bool=false)
    for f in readdir(auto_tappath)
        if endswith(f,".rb")
            if verbose
                println("Deleting $f...")
            end
            Base.rm(joinpath(auto_tappath,f))
        end
    end
end

"""
`translate_formula(pkg::Union{AbstractString,BrewPkg}; verbose::Bool=false)`

Given a formula `name`, return the fully-qualified name of a translated formula
if it is translatable.  Translation copies a `Homebrew/core` formula to
`$auto_tapname`, adding appropriate `cellar :any` and `root_url` lines to
any bottle stanzas.  This allows us to transparently install non-cellar-any
formulae from `Homebrew/core`.

This function is fairly strict, bailing out at every possible opportunity, and
returning the original name.  If a formula is non-translatable, it's possible
it needs manual intervention, check out the $tapname tap for examples.
"""
function translate_formula(pkg::StringOrPkg; verbose::Bool=false) end

function translate_formula(name::AbstractString; verbose::Bool=false)
    if verbose
        println("translation: beginning for $name")
    end

    path, tap_path = formula_tap(name)

    # We maintain a list of formulae that we WILL NOT translate. As an example,
    # 'xz' is automatically added as a dependency by Homebrew when a formula
    # has a `.tar.xz` source tarball.  This cannot be redirected to the
    # `staticfloat/juliatranslated` tap, causing diamonds of death where we have
    # the potential for both `xz` and `staticfloat/juliatranslated/xz` to
    # be in the dependency tree for a formula.
    translation_blacklist = ["xz"]
    if basename(name) in translation_blacklist
        if verbose
            println("translation: bailing because $name is in the translation blacklist")
        end
        return name
    end

    # Did we ask for any old name, or did we explicitly request a tap?
    if isempty(tap_path)
        # Bail if there is an overriding formula in our manually-curated tap
        if isfile(joinpath(tappath, "$(name).rb"))
            if verbose
                println("translation: using $tapname/$name for the source of our translation")
            end
            tap_path = tapname
            name = "$(tap_path)/$(path)"
        end
    else
        # If we explicitly asked for a tap, then make sure it's here!
        tap(tap_path)
    end

    # Bail if we have no bottles
    if !has_bottle(name)
        if verbose
            println("translation: bailing because $name has no bottles")
        end
        return name
    end

    # Delete any older translated formula if they exist
    auto_path = joinpath(auto_tappath, "$(path).rb")
    override_name = joinpath(auto_tapname, path)
    if isfile(auto_path)
        src_path = formula_path(name)
        if stat(auto_path).mtime < stat(src_path).mtime
            if verbose
                println("translation: deleting stale translation for $name")
            end
            delete_translated_formula(override_name; verbose=verbose)
        else
            if verbose
                println("translation: bailing becuase $name is already available in tap $auto_tapname")
            end
            return joinpath(auto_tapname, path)
        end
    end

    # Read formula source in, and also get a JSON representation of it
    obj = json(name)
    formula = read_formula(name)

    # Find bottle section. We allow 1 to 8 lines of code in a bottle stanza:
    # a root_url, a prefix, a cellar, a revision, and four OSX version bottles.

    ex = r"(?:\r\n|\r|\n)\s*bottle\s+do(?:\r\n|\r|\n)(?:[^\n]*(?:\r\n|\r|\n)){1,8}\s*end\s*(?:\r\n|\r|\n)"
    m = match(ex, formula)
    if m === nothing
        # This shouldn't happen, because we passed `has_bottle()` above
        @warn("Couldn't find bottle stanza in $name")
        return name
    end

    # We know there is no `cellar :any` or `cellar :any_skip_relocation` since
    # we made it past the `has_relocatable_bottle()` check.  Eliminate any
    # `cellar` lines still within the match, then replace that section with a
    # section that contains the `cellar :any` we rely so heavily upon.
    bottle_lines = split(m.match, "\n")

    # Eliminate any lines that start with "cellar" or "root_url"
    bottle_lines = filter(line -> !startswith(lstrip(line), "cellar"), bottle_lines)
    bottle_lines = filter(line -> !startswith(lstrip(line), "root_url"), bottle_lines)

    # Find at which line the "bottle do" actually starts
    bottle_idx = findfirst(line -> match(r"bottle\s+do", line) !== nothing, bottle_lines)

    # Add a "cellar :any" and "root_url" line to this formula just after the
    # `bottle do`.  Note that since `match()` returns  SubString's, we need to
    # explicitly convert our string to SubString; this should be fixed in 0.6

    # We should, however, preserve :any_skip_relocation if that is what this
    # bottle is marked as, which includes important bottles such as `cctools`.
    if occursin(":any_skip_relocation", m.match)
        insert!(bottle_lines, bottle_idx+1, SubString("    cellar :any_skip_relocation",1))
    else
        insert!(bottle_lines, bottle_idx+1, SubString("    cellar :any",1))
    end
    insert!(bottle_lines, bottle_idx+1, SubString("    root_url \"$(obj["bottle"]["stable"]["root_url"])\"",1))

    # Resynthesize the bottle stanza and embed it into `formula` once more
    bottle_stanza = join(bottle_lines, "\n")
    formula = formula[1:m.offset-1] * bottle_stanza * formula[m.offset+length(m.match):end]

    # Find any depends_on lines, substitute in any translated formulae
    adjustment = 0
    for m in eachmatch(r"depends_on\s+\"([^ ]+)\"", formula)
        # This is the path that this dependency would have if it has been translated
        dep_name = m.captures[1]
        auto_dep_path = joinpath(auto_tappath, "$(dep_name).rb")

        # If this dependency has been translated, then prepend "staticfloat/juliatranslated"
        # to it in the formula, so there is no confusion inside of Homebrew
        if isfile(auto_dep_path)
            if verbose
                println("translation: replacing dependency $dep_name because it's been translated before")
            end
            new_name = "$(auto_tapname)/$(dep_name)"
            offset = m.offsets[1]

            start_idx = offset-1+adjustment
            stop_idx = offset+length(dep_name)+adjustment
            formula = formula[1:start_idx] * new_name * formula[stop_idx:end]
            adjustment += length(auto_tapname) + 1
        end
    end

    # Write our patched formula out to our override tap
    write_formula(override_name, formula)

    # Read that formula in again as a JSON object, compare with the original
    new_obj = json(override_name)
    if !has_relocatable_bottle(override_name)
        @warn("New formula $override_name doesn't have a relocatable bottle despite our meddling")
        return name
    end

    # Wow.  We actually did it.
    if verbose
        println("translation: successfully finished for $name")
    end
    return override_name
end

function translate_formula(pkg::BrewPkg; verbose::Bool=false)
    return translate_formula(fullname(pkg); verbose=verbose)
end
