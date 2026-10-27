// Sharp SBS stereo - Pixel Perfect Clarity Version
texture BackBufferTex : COLOR;
sampler2D sBackBuffer { Texture = BackBufferTex; };

uniform float Strength <
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 0.05;
    ui_step = 0.001;
    ui_label = "Depth Strength";
> = 0.025;

uniform bool InvertDepth <
    ui_label = "Invert Depth";
> = false;

void VS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 uv : TEXCOORD0)
{
    uv = float2((id << 1) & 2, id & 2);
    position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float calculateLuminance(float3 color)
{
    return dot(color, float3(0.299, 0.587, 0.114));
}

// Pixel-perfect sampling to maintain clarity
float3 samplePixelPerfect(sampler2D tex, float2 uv)
{
    float2 texSize = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float2 pixelPos = uv * texSize;
    float2 alignedPos = round(pixelPos - 0.5) + 0.5;
    float2 alignedUV = alignedPos / texSize;
    return tex2D(tex, alignedUV).rgb;
}

float4 PS(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // For SBS, we need to render both eyes side by side
    if (uv.x < 0.5)
    {
        // Left eye: original image (maximum clarity)
        float2 leftUV = float2(uv.x * 2.0, uv.y);
        return float4(samplePixelPerfect(sBackBuffer, leftUV), 1.0);
    }
    else
    {
        // Right eye: shifted image based on luminance
        float2 rightUV = float2((uv.x - 0.5) * 2.0, uv.y);
        
        // Sample current pixel for luminance with perfect clarity
        float3 color = samplePixelPerfect(sBackBuffer, rightUV);
        float luminance = calculateLuminance(color);
        
        // Simple but effective depth calculation
        float depth = pow(luminance, 1.0);
        
        // NEW: Strong but clear pop effect
        if (InvertDepth) {
            // For pop mode: use a steeper curve and boost
            depth = pow(depth, 0.6); // Steeper curve for stronger pop
            depth = depth * 1.4; // Additional boost
            depth = saturate(depth);
            
            // Apply shift for pop
            rightUV.x -= depth * Strength * 1.8; // Stronger shift for pop
        } else {
            // For sink-in mode: normal curve
            rightUV.x += depth * Strength;
        }
        
        rightUV.x = clamp(rightUV.x, 0.001, 0.999);
        
        // Use pixel-perfect sampling for the shifted position
        float3 shiftedColor = samplePixelPerfect(sBackBuffer, rightUV);
        
        return float4(shiftedColor, 1.0);
    }
}

technique StereoLuminanceSBS
{
    pass
    {
        VertexShader = VS;
        PixelShader = PS;
    }
}