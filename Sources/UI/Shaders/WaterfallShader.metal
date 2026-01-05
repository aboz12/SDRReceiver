#include <metal_stdlib>
using namespace metal;

// Vertex shader input
struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

// Vertex shader output / Fragment shader input
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Uniforms for waterfall configuration
struct WaterfallUniforms {
    float minDb;        // Minimum dB value (e.g., -120)
    float maxDb;        // Maximum dB value (e.g., 0)
    float scrollOffset; // Vertical scroll offset for animation
    float time;         // Animation time
    float glowIntensity;// Glow effect intensity
};

// Vertex shader - simple pass-through for full-screen quad
vertex VertexOut waterfall_vertex(
    uint vertexID [[vertex_id]],
    constant float2 *vertices [[buffer(0)]]
) {
    VertexOut out;

    // Full-screen quad vertices
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };

    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];

    return out;
}

// Convert magnitude to color using a custom SDR-style palette
float4 magnitudeToColor(float magnitude, float time) {
    // Clamp magnitude to 0-1 range
    float m = saturate(magnitude);

    // Multi-stop gradient: black -> deep blue -> cyan -> green -> yellow -> red -> white
    float4 color;

    if (m < 0.15) {
        // Black to deep blue
        float t = m / 0.15;
        color = mix(float4(0.0, 0.0, 0.05, 1.0), float4(0.0, 0.1, 0.4, 1.0), t);
    } else if (m < 0.3) {
        // Deep blue to cyan
        float t = (m - 0.15) / 0.15;
        color = mix(float4(0.0, 0.1, 0.4, 1.0), float4(0.0, 0.8, 1.0, 1.0), t);
    } else if (m < 0.45) {
        // Cyan to green
        float t = (m - 0.3) / 0.15;
        color = mix(float4(0.0, 0.8, 1.0, 1.0), float4(0.0, 1.0, 0.3, 1.0), t);
    } else if (m < 0.6) {
        // Green to yellow
        float t = (m - 0.45) / 0.15;
        color = mix(float4(0.0, 1.0, 0.3, 1.0), float4(1.0, 1.0, 0.0, 1.0), t);
    } else if (m < 0.8) {
        // Yellow to red
        float t = (m - 0.6) / 0.2;
        color = mix(float4(1.0, 1.0, 0.0, 1.0), float4(1.0, 0.2, 0.0, 1.0), t);
    } else {
        // Red to white (hot spots)
        float t = (m - 0.8) / 0.2;
        color = mix(float4(1.0, 0.2, 0.0, 1.0), float4(1.0, 1.0, 1.0, 1.0), t);
    }

    return color;
}

// Fragment shader for waterfall display
fragment float4 waterfall_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> waterfallTexture [[texture(0)]],
    constant WaterfallUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    // Sample the waterfall data texture
    float2 uv = in.texCoord;

    // Apply scroll offset for smooth animation
    uv.y = fract(uv.y + uniforms.scrollOffset);

    float magnitude = waterfallTexture.sample(textureSampler, uv).r;

    // Normalize from dB range to 0-1
    float normalized = (magnitude - uniforms.minDb) / (uniforms.maxDb - uniforms.minDb);

    // Get base color
    float4 color = magnitudeToColor(normalized, uniforms.time);

    // Add subtle glow effect for strong signals
    if (uniforms.glowIntensity > 0.0 && normalized > 0.5) {
        float glow = (normalized - 0.5) * 2.0 * uniforms.glowIntensity;
        color.rgb += glow * 0.3;
    }

    return color;
}

// Spectrum line shader
struct SpectrumUniforms {
    float minDb;
    float maxDb;
    float lineWidth;
    float4 lineColor;
    float4 fillColor;
    float glowRadius;
};

fragment float4 spectrum_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> spectrumTexture [[texture(0)]],
    constant SpectrumUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float2 uv = in.texCoord;

    // Sample spectrum magnitude at this x position
    float magnitude = spectrumTexture.sample(textureSampler, float2(uv.x, 0.5)).r;

    // Normalize
    float normalized = (magnitude - uniforms.minDb) / (uniforms.maxDb - uniforms.minDb);
    float spectrumY = 1.0 - saturate(normalized);

    // Distance from the spectrum line
    float dist = abs(uv.y - spectrumY);

    // Line with anti-aliasing
    float lineAlpha = 1.0 - smoothstep(0.0, uniforms.lineWidth, dist);

    // Fill below the line
    float fillAlpha = uv.y > spectrumY ? 0.3 : 0.0;

    // Glow effect
    float glowAlpha = exp(-dist * dist / (uniforms.glowRadius * uniforms.glowRadius)) * 0.5;

    // Combine
    float4 color = uniforms.lineColor * lineAlpha;
    color += uniforms.fillColor * fillAlpha;
    color += uniforms.lineColor * glowAlpha * (1.0 - lineAlpha);

    return color;
}

// Glass blur kernel for liquid glass effect
kernel void gaussianBlur(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float &blurRadius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 sum = float4(0.0);
    float weightSum = 0.0;

    int radius = int(blurRadius);

    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            int2 samplePos = int2(gid) + int2(x, y);
            samplePos = clamp(samplePos, int2(0), int2(inTexture.get_width() - 1, inTexture.get_height() - 1));

            float weight = exp(-(x*x + y*y) / (2.0 * blurRadius * blurRadius));
            sum += inTexture.read(uint2(samplePos)) * weight;
            weightSum += weight;
        }
    }

    outTexture.write(sum / weightSum, gid);
}
