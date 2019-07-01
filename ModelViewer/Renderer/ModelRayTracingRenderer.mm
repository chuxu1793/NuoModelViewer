//
//  ModelRayTracingRenderer.m
//  ModelViewer
//
//  Created by middleware on 6/22/18.
//  Copyright © 2018 middleware. All rights reserved.
//

#import "ModelRayTracingRenderer.h"

#import "NuoLightSource.h"

#import "NuoCommandBuffer.h"
#import "NuoBufferSwapChain.h"
#import "NuoRayBuffer.h"
#import "NuoRayAccelerateStructure.h"

#include "NuoRayTracingRandom.h"
#include "NuoComputeEncoder.h"
#include "NuoRenderPassAttachment.h"



static const uint32_t kRandomBufferSize = 256;
static const uint32_t kRayBounce = 4;


@implementation ModelDirectLighting

@end


@interface ModelRayTracingShadowPerLight : NuoRayTracingRenderer

@property (nonatomic, readonly) NSArray<NuoRayBuffer*>* shadowRays;
@property (nonatomic, readonly) NSArray<id<MTLBuffer>>* shadowRayBuffers;
@property (nonatomic, readonly) NSArray<id<MTLBuffer>>* shadowIntersectionBuffers;

@property (nonatomic, weak) NuoLightSource* lightSource;

@property (nonatomic, readonly) NSArray<NuoRenderPassTarget*>* normalizedIllumination;

- (instancetype)initWithCommandQueue:(id<MTLCommandQueue>)commandQueue;

@end




@implementation ModelRayTracingShadowPerLight
{
    NuoComputePipeline* _shadowShadePipeline;
    NuoComputePipeline* _differentialPipeline;
    CGSize _drawableSize;
}


- (instancetype)initWithCommandQueue:(id<MTLCommandQueue>)commandQueue
{
    // use two channels for the opaque and translucent objects, respectivey
    //
    MTLPixelFormat format = MTLPixelFormatRGBA32Float;
    
    self = [super initWithCommandQueue:commandQueue
                       withPixelFormat:format
                       withTargetCount:6 /* 2 for opaque, 2 for translucent, 2 for virtual */];
    
    if (self)
    {
        _shadowShadePipeline = [[NuoComputePipeline alloc] initWithDevice:commandQueue.device
                                                             withFunction:@"shadow_contribute"];
        _differentialPipeline = [[NuoComputePipeline alloc] initWithDevice:commandQueue.device
                                                              withFunction:@"shadow_illuminate"];
        
        _shadowShadePipeline.name = @"Shadow Shade (Opaque)";
        _differentialPipeline.name = @"Illumination Normalizing";
        
        NuoRenderPassTarget* illumination[2];
        for (uint i = 0; i < 2; ++i)
        {
            illumination[i] = [[NuoRenderPassTarget alloc] initWithCommandQueue:commandQueue
                                                                withPixelFormat:format
                                                                withSampleCount:1];
            
            NuoRenderPassTarget* illum = illumination[i];
            
            illum.manageTargetTexture = YES;
            illum.sharedTargetTexture = NO;
            illum.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
            illum.colorAttachments[0].needWrite = YES;
            illum.name = @"Ray Tracing Normalized";
        }
        
        _normalizedIllumination = [[NSArray alloc] initWithObjects:illumination count:2];
    }
    
    return self;
}


- (void)setDrawableSize:(CGSize)drawableSize
{
    [super setDrawableSize:drawableSize];
    
    if (CGSizeEqualToSize(_drawableSize, drawableSize))
        return;
    
    _drawableSize = drawableSize;
    for (NuoRenderPassTarget* illum in _normalizedIllumination)
        illum.drawableSize = drawableSize;
    
    const size_t intersectionSize = drawableSize.width * drawableSize.height * kRayIntersectionStride;
    
    NuoRayBuffer* shadowRayBuffers[kNuoRayIndex_Size];
    id<MTLBuffer> intersectBuffers[kNuoRayIndex_Size];
    id<MTLBuffer> shadowRayMTL[kNuoRayIndex_Size];
    
    for (uint i = 0; i < kNuoRayIndex_Size; ++i)
    {
        shadowRayBuffers[i] = [[NuoRayBuffer alloc] initWithCommandQueue:self.commandQueue];
        shadowRayBuffers[i].dimension = _drawableSize;
        shadowRayMTL[i] = shadowRayBuffers[i].buffer;
        
        intersectBuffers[i] = [self.commandQueue.device newBufferWithLength:intersectionSize
                                                                    options:MTLResourceStorageModePrivate];
    }
    _shadowRays = [[NSArray alloc] initWithObjects:shadowRayBuffers count:kNuoRayIndex_Size];
    _shadowIntersectionBuffers = [[NSArray alloc] initWithObjects:intersectBuffers count:kNuoRayIndex_Size];
    _shadowRayBuffers = [[NSArray alloc] initWithObjects:shadowRayMTL count:kNuoRayIndex_Size];
}


- (void)runRayTraceShade:(NuoCommandBuffer*)commandBuffer
{
    for (uint i = 0; i < kNuoRayIndex_Size; ++i)
    {
        [self rayIntersect:commandBuffer withRays:_shadowRays[i]
                                 withIntersection:_shadowIntersectionBuffers[i]];
    }
    
    [self runRayTraceCompute:_shadowShadePipeline withCommandBuffer:commandBuffer
               withParameter:nil
              withExitantRay:_shadowRayBuffers
            withIntersection:_shadowIntersectionBuffers];
}



- (void)drawWithCommandBuffer:(NuoCommandBuffer*)commandBuffer
{
    [super drawWithCommandBuffer:commandBuffer];
    
    for (NuoRenderPassTarget* illum in _normalizedIllumination)
    {
        [illum retainRenderPassEndcoder:commandBuffer];
        [illum releaseRenderPassEndcoder];
    }
    
    NuoComputeEncoder* encoder = [_differentialPipeline encoderWithCommandBuffer:commandBuffer];
    
    NSArray<id<MTLTexture>>* textures = self.targetTextures;
    
    uint i = 0;
    
    // only opaque and translucent surfaces need normalization
    //
    for (; i < 4; ++i)
        [encoder setTexture:textures[i] atIndex:i];

    [encoder setTexture:_normalizedIllumination[0].targetTexture atIndex:i];
    [encoder setTexture:_normalizedIllumination[1].targetTexture atIndex:i+1];
    
    [encoder dispatch];
}



@end




@implementation ModelRayTracingRenderer
{
    NuoComputePipeline* _primaryRaysPipeline;
    NuoComputePipeline* _rayShadePipeline;
    
    NuoBufferSwapChain* _rayTraceUniform;
    NuoBufferSwapChain* _randomBuffers;
    
    ModelRayTracingShadowPerLight* _shadowPerLight[2];
    
    NuoRayBuffer* _incidentRaysBuffer;
    
    PNuoRayTracingRandom _rng;
}


- (instancetype)initWithCommandQueue:(id<MTLCommandQueue>)commandQueue
{
    self = [super initWithCommandQueue:commandQueue
                       withPixelFormat:MTLPixelFormatRGBA32Float withTargetCount:1];
    
    if (self)
    {
        _primaryRaysPipeline = [[NuoComputePipeline alloc] initWithDevice:commandQueue.device
                                                               withFunction:@"primary_ray_process"];
        _primaryRaysPipeline.name = @"Primary Ray Process";
        
        _rayShadePipeline = [[NuoComputePipeline alloc] initWithDevice:commandQueue.device
                                                          withFunction:@"incident_ray_process"];
        _rayShadePipeline.name = @"Incident Ray Shading";
        
        _rng = std::make_shared<NuoRayTracingRandom>(kRandomBufferSize, kRayBounce, 1);
        _rayTraceUniform = [[NuoBufferSwapChain alloc] initWithDevice:commandQueue.device
                                                       WithBufferSize:sizeof(NuoRayTracingUniforms)
                                                          withOptions:MTLResourceStorageModeManaged
                                                        withChainSize:kInFlightBufferCount];
        _randomBuffers = [[NuoBufferSwapChain alloc] initWithDevice:commandQueue.device
                                                     WithBufferSize:_rng->BytesSize()
                                                        withOptions:MTLResourceStorageModeManaged
                                                      withChainSize:kInFlightBufferCount];
        
        for (uint i = 0; i < 2; ++i)
            _shadowPerLight[i] = [[ModelRayTracingShadowPerLight alloc] initWithCommandQueue:commandQueue];
    }
    
    return self;
}


- (void)setDrawableSize:(CGSize)drawableSize
{
    [super setDrawableSize:drawableSize];
    
    for (ModelRayTracingShadowPerLight* renderer : _shadowPerLight)
        [renderer setDrawableSize:drawableSize];
    
    _incidentRaysBuffer = [[NuoRayBuffer alloc] initWithCommandQueue:self.commandQueue];
    _incidentRaysBuffer.dimension = drawableSize;
}


- (void)setLightSource:(NuoLightSource*)lightSource forIndex:(uint)index
{
    [_shadowPerLight[index] setLightSource:lightSource];
}


- (void)resetResources:(NuoCommandBuffer*)commandBuffer
{
    for (ModelRayTracingShadowPerLight* renderer : _shadowPerLight)
        [renderer resetResources:commandBuffer];
    
    [super resetResources:commandBuffer];
}


- (void)updateUniforms:(id<NuoRenderInFlight>)inFlight
{
    NuoRayTracingUniforms uniforms;
    
    for (uint i = 0; i < 2; ++i)
    {
        NuoLightSource* lightSource = _shadowPerLight[i].lightSource;
        const NuoMatrixFloat44 matrix = NuoMatrixRotation(lightSource.lightingRotationX, lightSource.lightingRotationY);
        
        NuoRayTracingLightSource* lightSourceRayTracing = &(uniforms.lightSources[i]);
        
        lightSourceRayTracing->direction = matrix._m;
        lightSourceRayTracing->density = lightSource.lightingDensity;
        
        // the code used to pass lightSource.shadowSoften into the shader, and the shader use it as diameter of
        // a disk which is distant from the lighted surface by the scene's dimension (i.e. maxDistance). in this
        // way, the calculatin is duplicated for each pixel each ray, and would even duplicate in multiple places
        // among different shaders.
        //
        // now, the lightSource.shadowSoften is used as tangent of theta, with a scale factor that tries to
        // make the effect as close to the old behavior as possible. and the consine value is calculated from that
        // and passed to the shader. this approach need calculate the value once per render pass
        //
        float thetaTan = lightSource.shadowSoften / 2.0 * 0.25;
        lightSourceRayTracing->coneAngleCosine = (1 / sqrt(thetaTan * thetaTan + 1));
    }
    
    uniforms.bounds.span = _sceneBounds.MaxDimension();
    uniforms.bounds.center = NuoVectorFloat4(_sceneBounds._center._vector.x,
                                             _sceneBounds._center._vector.y,
                                             _sceneBounds._center._vector.z, 1.0)._vector;
    uniforms.globalIllum = _globalIllum;
    
    [_rayTraceUniform updateBufferWithInFlight:inFlight withContent:&uniforms];
    
    id<MTLBuffer> randomBuffer = [_randomBuffers bufferForInFlight:inFlight];
    _rng->SetBuffer(randomBuffer.contents);
    _rng->UpdateBuffer();
    [randomBuffer didModifyRange:NSMakeRange(0, _rng->BytesSize())];
}


- (void)runRayTraceShade:(NuoCommandBuffer*)commandBuffer
{
    // the shadow maps in the screen space are integrated by the sub renderers.
    // the master ray tracing renderer integrates the overlay result, e.g. self-illumination
    
    [self updateUniforms:commandBuffer];
    [self primaryRayEmit:commandBuffer];
    
    id<MTLBuffer> rayTraceUniform = [_rayTraceUniform bufferForInFlight:commandBuffer];
    id<MTLBuffer> randomBuffer = [_randomBuffers bufferForInFlight:commandBuffer];
    
    if ([self primaryRayIntersect:commandBuffer])
    {
        // generate rays for the two light sources, from opaque objects
        //
        [self runRayTraceCompute:_primaryRaysPipeline withCommandBuffer:commandBuffer
                   withParameter:@[rayTraceUniform, randomBuffer,
                                   _shadowPerLight[0].shadowRayBuffers[kNuoRayIndex_OnOpaque],
                                   _shadowPerLight[1].shadowRayBuffers[kNuoRayIndex_OnOpaque],
                                   _incidentRaysBuffer.buffer]
                  withExitantRay:nil
                withIntersection:@[self.intersectionBuffer]];
    }
    
    [self updatePrimaryRayMask:kNuoRayIndex_OnTranslucent withCommandBuffer:commandBuffer];
    
    if ([self primaryRayIntersect:commandBuffer])
    {
        // generate rays for the two light sources, from translucent objects
        //
        [self runRayTraceCompute:_primaryRaysPipeline withCommandBuffer:commandBuffer
                   withParameter:@[rayTraceUniform, randomBuffer,
                                   _shadowPerLight[0].shadowRayBuffers[kNuoRayIndex_OnTranslucent],
                                   _shadowPerLight[1].shadowRayBuffers[kNuoRayIndex_OnTranslucent],
                                   _incidentRaysBuffer.buffer]
                  withExitantRay:nil
                withIntersection:@[self.intersectionBuffer]];
        
        for (uint i = 0; i < kRayBounce; ++i)
        {
            [self rayIntersect:commandBuffer withRays:_incidentRaysBuffer withIntersection:self.intersectionBuffer];
            
            [self runRayTraceCompute:_rayShadePipeline withCommandBuffer:commandBuffer
                       withParameter:@[rayTraceUniform, randomBuffer]
                      withExitantRay:@[_incidentRaysBuffer.buffer]
                    withIntersection:@[self.intersectionBuffer]];
        }
    }
        
    for (uint i = 0; i < 2; ++i)
    {
        // sub renderers detect intersection for each light source
        // and accumulates the samplings
        //
        [_shadowPerLight[i] setRayStructure:self.rayStructure];
        [_shadowPerLight[i] drawWithCommandBuffer:commandBuffer];
    }
}


- (id<MTLTexture>)shadowForLightSource:(uint)index withMask:(NuoSceneMask)mask
{
    uint i = (mask == kNuoSceneMask_Opaque ? 0 : 1);
    return _shadowPerLight[index].normalizedIllumination[i].targetTexture;
}



- (NSArray<ModelDirectLighting*>*)directLight
{
    ModelDirectLighting* lighting[2];
    
    for (uint i = 0; i < 2; ++i)
    {
        NSArray* textures = _shadowPerLight[i].targetTextures;
        
        lighting[i] = [ModelDirectLighting new];
        lighting[i].lighting = textures[0];
        lighting[i].blocked = textures[1];
    }
    
    return [[NSArray alloc] initWithObjects:lighting count:2];
}



@end
