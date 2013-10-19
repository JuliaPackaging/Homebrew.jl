## This is an excerpt from my work on the sf/debugtools branch.
## I'm keeping it as a separate file as I hope to someday have these tools in base

function shlib_list()
    dynamic_libraries = Array(String,0)

    numImages = ccall( cglobal("_dyld_image_count"), Cint, (), )

    # start at 1 instead of 0 to skip self
    for i in 1:numImages-1
        name = bytestring(ccall( cglobal("_dyld_get_image_name"), Ptr{Uint8}, (Uint32,), uint32(i)))
        push!(dynamic_libraries, name)
    end

    dynamic_libraries
end