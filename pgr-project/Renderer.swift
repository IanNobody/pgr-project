//
//  Renderer.swift
//  pgr-project
//
//  Created by Šimon Strýček on 27.11.2022.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd
import Accelerate

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    var computePipelineState: MTLComputePipelineState
    var depthState: MTLDepthStencilState
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)

    var dynamicUniformBuffer: MTLBuffer
    var uniformBufferOffset = 0
    var uniformBufferIndex = 0

    var woodColorMap: MTLTexture
    var floorColorMap: MTLTexture

    var vertexBuffer: MTLBuffer
    var indexBuffer: MTLBuffer
    var normalBuffer: MTLBuffer
    var texCoordsBuffer: MTLBuffer
    var modelConstantBuffer: MTLBuffer

    var uniforms: UnsafeMutablePointer<Uniforms>

    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    var viewMatrix: matrix_float4x4 = matrix_float4x4()
    var rotation: Float = 0.3

    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!

        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
        self.dynamicUniformBuffer = self.device.makeBuffer(length:uniformBufferSize,
                                                           options:[MTLResourceOptions.storageModeShared])!
        self.dynamicUniformBuffer.label = "UniformBuffer"

        self.vertexBuffer = self.device.makeBuffer(bytes: Scene.sceneObjects[0].vertices, length: Scene.sceneObjects[0].vertices.count * MemoryLayout<Float>.size, options: [])!
        self.indexBuffer = self.device.makeBuffer(bytes: Scene.sceneObjects[0].indices, length: Scene.sceneObjects[0].indices.count * MemoryLayout<UInt16>.size, options: [])!
        self.normalBuffer = self.device.makeBuffer(bytes: Scene.sceneObjects[0].normals, length: Scene.sceneObjects[0].normals.count * MemoryLayout<Float>.size, options: [])!
        self.texCoordsBuffer = self.device.makeBuffer(bytes: Scene.sceneObjects[0].texCoords, length: Scene.sceneObjects[0].texCoords.count * MemoryLayout<Float>.size, options: [])!
        self.modelConstantBuffer = self.device.makeBuffer(bytes: &(Scene.sceneObjects[0].modelMatrix), length: MemoryLayout<simd_float4x4>.size, options: [])!

        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to:Uniforms.self, capacity:1)

        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1

        let mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()
        let cmpVertexDescriptor = Renderer.buildComputeVertexDescriptor()

        do {
            pipelineState = try Renderer.buildRenderPipelineWithDevice(device: device,
                                                                       metalKitView: metalKitView,
                                                                       mtlVertexDescriptor: mtlVertexDescriptor)
            computePipelineState = try Renderer.buildComputePipelineWithDevice(device: device,
                                                                               metalKitView: metalKitView,
                                                                               mtlVertexDescriptor: cmpVertexDescriptor)
        } catch {
            print("Unable to compile render pipeline state.  Error info: \(error)")
            return nil
        }

        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDescriptor.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor:depthStateDescriptor)!

        do {
            woodColorMap = try Renderer.loadTexture(device: device, texturePath: "~/Downloads/wood-texture.jpg")
            floorColorMap = try Renderer.loadTexture(device: device, texturePath: "~/Downloads/floor-texture.jpg")

        } catch {
            print("Unable to load textures. Error info: \(error)")
            return nil
        }

        super.init()
    }

    class func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        // Create a Metal vertex descriptor specifying how vertices will by laid out for input into our render
        //   pipeline and how we'll layout our Model IO vertices

        let mtlVertexDescriptor = MTLVertexDescriptor()

        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue

        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].format = MTLVertexFormat.float2
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue

        mtlVertexDescriptor.attributes[VertexAttribute.normal.rawValue].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[VertexAttribute.normal.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.normal.rawValue].bufferIndex = BufferIndex.normal.rawValue

        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = 12
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepFunction = MTLVertexStepFunction.perVertex

        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stride = 8
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = MTLVertexStepFunction.perVertex

        mtlVertexDescriptor.layouts[BufferIndex.normal.rawValue].stride = 12
        mtlVertexDescriptor.layouts[BufferIndex.normal.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.normal.rawValue].stepFunction = MTLVertexStepFunction.perVertex

        return mtlVertexDescriptor
    }

    class func buildComputeVertexDescriptor() -> MTLVertexDescriptor {
        // Create a Metal vertex descriptor specifying how vertices will by laid out for input into our render
        //   pipeline and how we'll layout our Model IO vertices

        let mtlVertexDescriptor = MTLVertexDescriptor()

        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue

        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].format = MTLVertexFormat.float2
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue

        mtlVertexDescriptor.attributes[VertexAttribute.normal.rawValue].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[VertexAttribute.normal.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.normal.rawValue].bufferIndex = BufferIndex.normal.rawValue

        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = 12
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepFunction = MTLVertexStepFunction.perVertex

        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stride = 8
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = MTLVertexStepFunction.perVertex

        mtlVertexDescriptor.layouts[BufferIndex.normal.rawValue].stride = 12
        mtlVertexDescriptor.layouts[BufferIndex.normal.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.normal.rawValue].stepFunction = MTLVertexStepFunction.perVertex

        return mtlVertexDescriptor
    }

    class func buildRenderPipelineWithDevice(device: MTLDevice,
                                             metalKitView: MTKView,
                                             mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()

        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.rasterSampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor

        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    class func buildComputePipelineWithDevice(device: MTLDevice,
                                              metalKitView: MTKView,
                                              mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLComputePipelineState {
        let library = device.makeDefaultLibrary()
        let computeFunction = library?.makeFunction(name: "illumination")
        return try device.makeComputePipelineState(function: computeFunction!)
    }

    class func loadTexture(device: MTLDevice,
                           texturePath: NSString) throws -> MTLTexture {
        /// Load texture data with optimal parameters for sampling

        let textureLoader = MTKTextureLoader(device: device)

        let textureLoaderOptions = [
            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue)
        ]

        let path: NSString = texturePath
        return try textureLoader.newTexture(
            URL: NSURL.fileURL(withPath: path.expandingTildeInPath),
            options: textureLoaderOptions
        )
    }

    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering

        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight

        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex

        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset).bindMemory(to:Uniforms.self, capacity:1)
    }

    private func updateGameState() {
        /// Update any game state before rendering

        uniforms[0].projectionMatrix = projectionMatrix

        let rotationAxis = SIMD3<Float>(1, 1, 0)
        let rotationMatrix = matrix4x4_rotation(radians: rotation, axis: rotationAxis)
        uniforms[0].viewMatrix = matrix4x4_translation(0.0, 0.0, -5.0)// matrix_multiply(matrix4x4_translation(0.0, 0.0, -5.0), rotationMatrix)
        rotation += 0.01
    }

    func swizzleBGRA8toRGBA8(_ bytes: UnsafeMutableRawPointer, width: Int, height: Int) {
        var sourceBuffer = vImage_Buffer(data: bytes,
                                         height: vImagePixelCount(height),
                                         width: vImagePixelCount(width),
                                         rowBytes: width * 4)
        var destBuffer = vImage_Buffer(data: bytes,
                                       height: vImagePixelCount(height),
                                       width: vImagePixelCount(width),
                                       rowBytes: width * 4)
        var swizzleMask: [UInt8] = [ 2, 1, 0, 3 ] // BGRA -> RGBA
        vImagePermuteChannels_ARGB8888(&sourceBuffer, &destBuffer, &swizzleMask, vImage_Flags(kvImageNoFlags))
    }

    func makeImage(for texture: MTLTexture) -> CGImage? {
        assert(texture.pixelFormat == .bgra8Unorm_srgb)

        let width = texture.width
        let height = texture.height
        let pixelByteCount = 4 * MemoryLayout<UInt8>.size
        let imageBytesPerRow = width * pixelByteCount
        let imageByteCount = imageBytesPerRow * height
        let imageBytes = UnsafeMutableRawPointer.allocate(byteCount: imageByteCount, alignment: pixelByteCount)
        defer {
            imageBytes.deallocate()
        }

        texture.getBytes(imageBytes,
                         bytesPerRow: imageBytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height),
                         mipmapLevel: 0)


        swizzleBGRA8toRGBA8(imageBytes, width: width, height: height)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let bitmapContext = CGContext(data: nil,
                                            width: width,
                                            height: height,
                                            bitsPerComponent: 8,
                                            bytesPerRow: imageBytesPerRow,
                                            space: colorSpace,
                                            bitmapInfo: bitmapInfo) else { return nil }
        bitmapContext.data?.copyMemory(from: imageBytes, byteCount: imageByteCount)
        let image = bitmapContext.makeImage()
        return image
    }

    func writeTexture(_ texture: MTLTexture, url: URL) {
        guard let image = makeImage(for: texture) else { return }

        if let imageDestination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) {
            CGImageDestinationAddImage(imageDestination, image, nil)
            CGImageDestinationFinalize(imageDestination)
        }
    }

    func draw(in view: MTKView) {
        /// Per frame updates hare

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            self.updateDynamicBufferState()
            
            self.updateGameState()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor

            //let renderEncoder = commandBuffer.makeComputeCommandEncoder()
            //renderEncoder?.setComputePipelineState(computePipelineState)


            if let renderPassDescriptor = renderPassDescriptor {
                /// Final pass rendering code here
                if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    renderEncoder.label = "Primary Render Encoder"

                    var index: Int = 0

                    for i in 0..<Scene.sceneObjects.count {
                        self.vertexBuffer = self.device.makeBuffer(bytes: Scene.sceneObjects[i].vertices, length: Scene.sceneObjects[i].vertices.count * MemoryLayout<Float>.size, options: [])!
                        self.indexBuffer = self.device.makeBuffer(bytes: Scene.sceneObjects[i].indices, length: Scene.sceneObjects[i].indices.count * MemoryLayout<UInt16>.size, options: [])!

                        self.normalBuffer = self.device.makeBuffer(bytes: Scene.sceneObjects[i].normals, length: Scene.sceneObjects[i].normals.count * MemoryLayout<Float>.size, options: [])!

                        self.texCoordsBuffer = self.device.makeBuffer(bytes: Scene.sceneObjects[i].texCoords, length: Scene.sceneObjects[i].texCoords.count * MemoryLayout<Float>.size, options: [])!

                        self.modelConstantBuffer = self.device.makeBuffer(bytes: &(Scene.sceneObjects[i].modelMatrix), length: MemoryLayout<simd_float4x4>.size, options: [])!

                        renderEncoder.pushDebugGroup("Draw scene object")

                        //renderEncoder.setCullMode(.back)

                        renderEncoder.setFrontFacing(.counterClockwise)

                        renderEncoder.setRenderPipelineState(pipelineState)

                        renderEncoder.setDepthStencilState(depthState)

                        renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                        renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                        renderEncoder.setVertexBuffer(modelConstantBuffer, offset: 0, index: 3)

                        if index == 0 {
                            renderEncoder.setFragmentTexture(woodColorMap, index: TextureIndex.color.rawValue)
                        } else {
                            renderEncoder.setFragmentTexture(floorColorMap, index: TextureIndex.color.rawValue)
                        }

                        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: BufferIndex.meshPositions.rawValue)
                        renderEncoder.setVertexBuffer(texCoordsBuffer, offset: 0, index: BufferIndex.meshGenerics.rawValue)
                        renderEncoder.setVertexBuffer(normalBuffer, offset: 0, index: BufferIndex.normal.rawValue)

                        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                            indexCount: Scene.sceneObjects[i].indices.count,
                                                            indexType: .uint16,
                                                            indexBuffer: indexBuffer,
                                                            indexBufferOffset: 0)

                        renderEncoder.popDebugGroup()
                        index+=1
                    }

                    /// Writing to textures:
                    //writeTexture(woodColorMap, url: NSURL.fileURL(withPath: NSString("~/Downloads/tex.jpg").expandingTildeInPath))
                    
                    renderEncoder.endEncoding()
                    
                    if let drawable = view.currentDrawable {
                        commandBuffer.present(drawable)
                    }
                }
            }
            
            commandBuffer.commit()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
    }
}
