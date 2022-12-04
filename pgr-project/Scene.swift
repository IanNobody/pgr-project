//
//  Scene.swift
//  pgr-project
//
//  Created by Šimon Strýček on 04.12.2022.
//

class Scene {
    public static var sceneObjects: [SceneObject] = [cube, floor]
    public static var sceneLight = Light(position: SIMD3<Float>(10, 10, 10),
                                         color: SIMD3<Float>(1, 1, 1))

    private static var cube = SceneObject(
        vertices: [-1, -1,  1, // 0 (L-B-F)
                    1, -1,  1, // 1 (R-B-F)
                   -1,  1,  1, // 2 (L-T-F)
                    1,  1,  1, // 3 (R-T-F)
                   -1, -1, -1, // 4 (L-B-B)
                    1, -1, -1, // 5 (R-B-B)
                   -1,  1, -1, // 6 (L-T-B)
                    1,  1, -1],// 7 (R-T-B)
        indices: [0, 1, 2,
                  1, 3, 2,
                  2, 3, 6,
                  3, 6, 7,
                  6, 5, 4,
                  5, 7, 6,
                  0, 4, 2,
                  4, 6, 2,
                  1, 3, 5,
                  5, 7, 3,
                  1, 0, 4,
                  1, 4, 5],
        texCoords: [0, 0, 1, 0, 0, 1,
                    1, 0, 1, 1, 0, 1,
                    0, 0, 1, 0, 0, 1,
                    1, 0, 1, 1, 0, 1,
                    0, 0, 1, 0, 0, 1,
                    1, 0, 1, 1, 0, 1,
                    0, 0, 1, 0, 0, 1,
                    1, 0, 1, 1, 0, 1,
                    0, 0, 1, 0, 0, 1,
                    1, 0, 1, 1, 0, 1,
                    0, 0, 1, 0, 0, 1,
                    1, 0, 1, 1, 0, 1],
        normals: [ 0,  0,  1,  0,  0,  1,  0,  0,  1,
                   0,  0,  1,  0,  0,  1,  0,  0,  1,
                   0,  1,  0,  0,  1,  0,  0,  1,  0,
                   0,  1,  0,  0,  1,  0,  0,  1,  0,
                   0,  0, -1,  0,  0, -1,  0,  0, -1,
                   0,  0, -1,  0,  0, -1,  0,  0, -1,
                  -1,  0,  0, -1,  0,  0, -1,  0,  0,
                  -1,  0,  0, -1,  0,  0, -1,  0,  0,
                   1,  0,  0,  1,  0,  0,  1,  0,  0,
                   1,  0,  0,  1,  0,  0,  1,  0,  0,
                   0, -1,  0,  0, -1,  0,  0, -1,  0,
                   0, -1,  0,  0, -1,  0,  0, -1,  0],
        modelMatrix: simd_float4x4([1, 0  , 0, 0],
                                   [0, 1  , 0, 0],
                                   [0, 0  , 1, 0],
                                   [0, 1.01, 0, 1])
    )

    public static var floor = SceneObject(
        vertices: [-5, 0, -5,
                    5, 0, -5,
                   -5, 0,  5,
                    5, 0,  5],
        indices: [0, 1, 2,
                  2, 1, 3],
        texCoords: [0, 1,
                    1, 1,
                    0, 0,
                    1, 0],
        normals: [0, 1, 0,
                  0, 1, 0,
                  0, 1, 0,
                  0, 1, 0],
        modelMatrix: simd_float4x4([1, 0, 0, 0],
                                   [0, 1, 0, 0],
                                   [0, 0, 1, 0],
                                   [0, 0, 0, 1])
    )
}

struct SceneObject {
    var vertices: [Float]
    var indices: [UInt16]
    var texCoords: [Float]
    var normals: [Float]
    var modelMatrix: simd_float4x4
}
