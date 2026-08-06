function get_geo_bbox(z, x, y)
    #@see https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames

    n = 2^z
    lon_min = x / n * 360.0 - 180.0
    lat_max = atan(sinh(π * (1 - 2 * y / n))) |> rad2deg

    lon_max = (x + 1) / n * 360.0 - 180.0
    lat_min = atan(sinh(π * (1 - 2 * (y + 1) / n))) |> rad2deg

    return Extent(X=(lon_min, lon_max), Y=(lat_min, lat_max))
end

function to_image(dggs_array::DGGSArray, lon_dim, lat_dim)
    matrix = to_geo_array(dggs_array, lon_dim, lat_dim) |> collect |> x -> replace!(x, missing => 1, NaN => 1)

    # Normalize matrix to [0, 1]
    attrs = DD.metadata(dggs_array)
    minval, maxval = if "actual_range" in keys(attrs)
        attrs["actual_range"]
    elseif "valid_range" in keys(attrs)
        attrs["valid_range"]
    else
        extrema(matrix)
    end

    norm_matrix = (matrix .- minval) ./ (maxval - minval + eps())

    norm_matrix = norm_matrix[1:length(lon_dim), length(lat_dim):-1:1]'
    img = colorview(RGB, reinterpret(RGB{Float32}, [get(ColorSchemes.viridis, v) for v in norm_matrix]))
    return img
end

struct Collection
    id::String
    dggs_pyramid::DGGSPyramid
    transform::Function
end

function to_image(dggs_ds::DGGSDataset, lon_dim, lat_dim, transform::Function)
    geo_ds = to_geo_dataset(dggs_ds, lon_dim, lat_dim)
    img = Matrix{RGBA{Float16}}(undef, length(lon_dim), length(lat_dim))
    for i in CartesianIndices(img)
        img[i] = transform(geo_ds, i)
    end
    img = img[1:length(lon_dim), length(lat_dim):-1:1]'
    return img
end

function has_overlap(dggs::Union{DGGSArray,DGGSDataset,DGGSPyramid}, lon_dim::X, lat_dim::Y)
    x1, x2 = dggs.bbox.X
    y1, y2 = dggs.bbox.Y

    if x1 <= minimum(lon_dim) <= x2 && y1 <= minimum(lat_dim) <= y2
        return true
    end

    if x1 <= maximum(lon_dim) <= x2 && y1 <= minimum(lat_dim) <= y2
        return true
    end

    if x1 <= minimum(lon_dim) <= x2 && y1 <= maximum(lat_dim) <= y2
        return true
    end
    if x1 <= maximum(lon_dim) <= x2 && y1 <= maximum(lat_dim) <= y2
        return true
    end

    return false
end

function request_tile(req, collectionId, collections, z, x, y)
    z = parse(Int, z)
    y = parse(Int, y)
    x = parse(Int, x)
    bbox = get_geo_bbox(z, x, y)
    lon_dim = range(bbox.X..., length=256) |> X
    lat_dim = range(bbox.Y..., length=256) |> Y

    request_collection_map(req, collectionId, collections; lon_dim=lon_dim, lat_dim=lat_dim)
end

function request_collection_map(req, collectionId, collections; lon_dim=nothing, lat_dim=nothing)
    collection = collections[collectionId]
    dggs_pyramid = collection.dggs_pyramid

    if isnothing(lon_dim) || isnothing(lat_dim)
        geo_bbox = dggs_pyramid.bbox
        aspect_ratio = (geo_bbox.X[2] - geo_bbox.X[1]) / (geo_bbox.Y[2] - geo_bbox.Y[1])
        height = 400
        lon_dim = X(range(geo_bbox.X..., length=aspect_ratio * height |> round |> Int))
        lat_dim = Y(range(geo_bbox.Y..., length=height))
    end

    resolution = DGGSMakie.get_resolution(dggs_pyramid, lon_dim, lat_dim)
    dggs_ds = dggs_pyramid[resolution]

    if !has_overlap(dggs_pyramid, lon_dim, lat_dim)
        return HTTP.Response(404, "Requested area outside of bbox")
    end

    img = to_image(dggs_ds, lon_dim, lat_dim, collection.transform)

    io = IOBuffer()
    save(FileIO.Stream(format"PNG", io), img)
    response_headers = [
        "Content-Type" => "image/png",
        "Access-Control-Allow-Origin" => "*",
    ]
    response = HTTP.Response(200, response_headers, io.data)
    return response
end
