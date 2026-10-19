shader_type sky;

void sky() {
    // A beautiful sky gradient
    // Position is in range [0, 1] from horizon to zenith
    vec3 horizon = vec3(0.85, 0.95, 1.0);  # Light blue horizon
    vec3 zenith = vec3(0.2, 0.4, 0.8);     # Deep blue zenith

    // Simple gradient based on V coordinate (vertical position)
    // V goes from 0 (bottom/horizon) to 1 (top/zenith)
    float v = position.y;  # This is the V coordinate in screen space

    // Mix between horizon and zenith
    vec3 color = mix(horizon, zenith, v);

    // Add some atmospheric scattering effect
    float rayleigh = 0.0028 * pow(1.0 - dot(normalize(vec3(0.0, 1.0, 0.0)), normalize(view_dir)), 4.0);
    color += rayleigh * vec3(1.0, 0.8, 0.5) * 0.1;

    COLOR = color;
}