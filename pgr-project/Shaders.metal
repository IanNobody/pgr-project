//
//  Shaders.metal
//  pgr-project
//
//  Created by Šimon Strýček on 27.11.2022.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
    float3 normal [[attribute(VertexAttributeNormal)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;

typedef struct
{
    float4 position;
    float3 color;
} Light;

kernel void illumination(Vertex in [[stage_in]],
                         constant Light & light [[ buffer(1) ]],
                         texture2d<half> textureColor [[ texture(0) ]],
                         texture2d<half> lightMap [[ texture(1) ]])
{

}

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                               constant ModelConstants & modelConstants [[ buffer(3) ]])
{
    ColorInOut out;

    float4 position = float4(in.position, 1.0);
    matrix_float4x4 transform = uniforms.projectionMatrix * uniforms.viewMatrix * modelConstants.modelMatrix;
    out.position = transform * position;
    out.texCoord = in.texCoord;

    return out;
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                               texture2d<half> colorMap     [[ texture(TextureIndexColor) ]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    half4 colorSample   = colorMap.sample(colorSampler, in.texCoord.xy);

    return float4(colorSample);
}
