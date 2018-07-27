@static if VERSION < v"0.7-" ? is_apple() : Sys.isapple()
    using Homebrew
    Homebrew.update()
end
