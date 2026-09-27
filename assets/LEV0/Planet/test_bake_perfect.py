import bpy
import os
import math

print("=== STARTING PERFECT PLANET & RING BAKE ===")

output_dir = r"C:\Users\MyBook Hype AMD\Documents\Spacesky\assets\Planet"
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 1

# -------------------------------------------------------------------
# 1. PROCESS PLANET (Icosphere)
# -------------------------------------------------------------------
planet_obj = bpy.data.objects.get("Icosphere")
if planet_obj:
    print("Processing Planet (Icosphere)...")
    bpy.context.view_layer.objects.active = planet_obj
    bpy.ops.object.select_all(action='DESELECT')
    planet_obj.select_set(True)
    
    # Ensure proper UV unwrap: Sphere Projection
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.sphere_project(clip_to_bounds=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    
    mat = planet_obj.active_material
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    out_node = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
    
    # Color Ramp.001 is the planet color
    cr_color = nodes.get("Color Ramp.001")
    bump_node = nodes.get("Bump.001")
    
    # Setup Emission for Albedo bake
    em_bake = nodes.new('ShaderNodeEmission')
    em_bake.inputs['Strength'].default_value = 1.0
    links.new(cr_color.outputs['Color'], em_bake.inputs['Color'])
    links.new(em_bake.outputs['Emission'], out_node.inputs['Surface'])
    
    img_albedo = bpy.data.images.new("planet_albedo_new", width=2048, height=2048, alpha=False)
    tex_node = nodes.new('ShaderNodeTexImage')
    tex_node.image = img_albedo
    nodes.active = tex_node
    
    print("Baking planet albedo (EMIT)...")
    bpy.ops.object.bake(type='EMIT')
    
    albedo_file = os.path.join(output_dir, "planet_albedo.png")
    img_albedo.filepath_raw = albedo_file
    img_albedo.file_format = 'PNG'
    img_albedo.save()
    print("Saved planet albedo to:", albedo_file)
    
    # Setup Normal bake
    orig_bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    links.new(orig_bsdf.outputs['BSDF'], out_node.inputs['Surface'])
    img_normal = bpy.data.images.new("planet_normal_new", width=2048, height=2048, alpha=False)
    tex_node.image = img_normal
    print("Baking planet normal...")
    bpy.ops.object.bake(type='NORMAL')
    
    normal_file = os.path.join(output_dir, "planet_normal.png")
    img_normal.filepath_raw = normal_file
    img_normal.file_format = 'PNG'
    img_normal.save()
    print("Saved planet normal to:", normal_file)

# -------------------------------------------------------------------
# 2. PROCESS RINGS (Circle)
# -------------------------------------------------------------------
rings_obj = bpy.data.objects.get("Circle")
if rings_obj:
    print("Processing Rings (Circle)...")
    bpy.context.view_layer.objects.active = rings_obj
    bpy.ops.object.select_all(action='DESELECT')
    rings_obj.select_set(True)
    
    # Unwrap Circle properly (Project from top view: X and Y mapped to UV 0..1)
    mesh = rings_obj.data
    uv_layer = mesh.uv_layers.active
    if not uv_layer:
        uv_layer = mesh.uv_layers.new(name="UVMap")
        
    # Calculate bounds for top-down UV
    coords = [v.co for v in mesh.vertices]
    min_x = min(c.x for c in coords)
    max_x = max(c.x for c in coords)
    min_y = min(c.y for c in coords)
    max_y = max(c.y for c in coords)
    range_x = max_x - min_x if max_x != min_x else 1.0
    range_y = max_y - min_y if max_y != min_y else 1.0
    
    for poly in mesh.polygons:
        for loop_idx in poly.loop_indices:
            v_idx = mesh.loops[loop_idx].vertex_index
            v_co = mesh.vertices[v_idx].co
            u = (v_co.x - min_x) / range_x
            v = (v_co.y - min_y) / range_y
            uv_layer.data[loop_idx].uv = (u, v)
            
    print("Circle UV unwrapped top-down successfully.")
    
    mat_r = rings_obj.active_material
    r_nodes = mat_r.node_tree.nodes
    r_links = mat_r.node_tree.links
    r_out = next(n for n in r_nodes if n.type == 'OUTPUT_MATERIAL')
    
    em_color_node = r_nodes.get("Emission")
    mix_node = r_nodes.get("Mix.001")
    
    # 2a. Bake Ring Color
    em_bake_r = r_nodes.new('ShaderNodeEmission')
    em_bake_r.inputs['Strength'].default_value = 1.0
    if em_color_node and em_color_node.inputs['Color'].is_linked:
        r_links.new(em_color_node.inputs['Color'].links[0].from_socket, em_bake_r.inputs['Color'])
    r_links.new(em_bake_r.outputs['Emission'], r_out.inputs['Surface'])
    
    img_rings_col = bpy.data.images.new("rings_color_bake", width=2048, height=2048, alpha=False)
    r_tex_node = r_nodes.new('ShaderNodeTexImage')
    r_tex_node.image = img_rings_col
    r_nodes.active = r_tex_node
    
    print("Baking rings color...")
    bpy.ops.object.bake(type='EMIT')
    
    # 2b. Bake Ring Alpha (Mix.001)
    if mix_node and mix_node.outputs[0].is_linked:
        r_links.new(mix_node.outputs[0], em_bake_r.inputs['Color'])
        
    img_rings_alpha = bpy.data.images.new("rings_alpha_bake", width=2048, height=2048, alpha=False)
    r_tex_node.image = img_rings_alpha
    
    print("Baking rings alpha...")
    bpy.ops.object.bake(type='EMIT')
    
    # Combine Color and Alpha into single RGBA image
    col_px = list(img_rings_col.pixels)
    alpha_px = list(img_rings_alpha.pixels)
    rgba_px = []
    for i in range(len(col_px) // 4):
        r = col_px[i*4]
        g = col_px[i*4 + 1]
        b = col_px[i*4 + 2]
        # In mix_node: alpha factor was used to mix with Transparent BSDF
        a = alpha_px[i*4] 
        rgba_px.extend([r, g, b, a])
        
    img_rings_final = bpy.data.images.new("rings_albedo_final", width=2048, height=2048, alpha=True)
    img_rings_final.pixels = rgba_px
    rings_file = os.path.join(output_dir, "rings_albedo.png")
    img_rings_final.filepath_raw = rings_file
    img_rings_final.file_format = 'PNG'
    img_rings_final.save()
    print("Saved combined rings albedo to:", rings_file)

# -------------------------------------------------------------------
# 3. REBUILD CLEAN PBR MATERIALS AND EXPORT GLB
# -------------------------------------------------------------------
print("Rebuilding clean PBR materials...")

# Planet Material
p_mat = bpy.data.materials.new("Planet_PBR")
p_mat.use_nodes = True
p_nodes = p_mat.node_tree.nodes
p_links = p_mat.node_tree.links
p_nodes.clear()

p_out = p_nodes.new('ShaderNodeOutputMaterial')
p_bsdf = p_nodes.new('ShaderNodeBsdfPrincipled')
p_links.new(p_bsdf.outputs['BSDF'], p_out.inputs['Surface'])

p_tex = p_nodes.new('ShaderNodeTexImage')
p_tex.image = bpy.data.images.load(os.path.join(output_dir, "planet_albedo.png"))
p_links.new(p_tex.outputs['Color'], p_bsdf.inputs['Base Color'])

p_norm = p_nodes.new('ShaderNodeTexImage')
p_norm.image = bpy.data.images.load(os.path.join(output_dir, "planet_normal.png"))
p_norm.image.colorspace_settings.name = 'Non-Color'
p_nmap = p_nodes.new('ShaderNodeNormalMap')
p_links.new(p_norm.outputs['Color'], p_nmap.inputs['Color'])
p_links.new(p_nmap.outputs['Normal'], p_bsdf.inputs['Normal'])

planet_obj.data.materials.clear()
planet_obj.data.materials.append(p_mat)

# Rings Material
r_mat = bpy.data.materials.new("Rings_PBR")
r_mat.use_nodes = True
r_mat.blend_method = 'BLEND'
r_nodes = r_mat.node_tree.nodes
r_links = r_mat.node_tree.links
r_nodes.clear()

r_out = r_nodes.new('ShaderNodeOutputMaterial')
r_bsdf = r_nodes.new('ShaderNodeBsdfPrincipled')
r_links.new(r_bsdf.outputs['BSDF'], r_out.inputs['Surface'])

r_tex = r_nodes.new('ShaderNodeTexImage')
r_tex.image = bpy.data.images.load(os.path.join(output_dir, "rings_albedo.png"))
r_links.new(r_tex.outputs['Color'], r_bsdf.inputs['Base Color'])
r_links.new(r_tex.outputs['Alpha'], r_bsdf.inputs['Alpha'])
r_links.new(r_tex.outputs['Color'], r_bsdf.inputs['Emission Color'])
r_bsdf.inputs['Emission Strength'].default_value = 2.0

rings_obj.data.materials.clear()
rings_obj.data.materials.append(r_mat)

# Export selected
bpy.ops.object.select_all(action='DESELECT')
planet_obj.select_set(True)
rings_obj.select_set(True)

glb_file = os.path.join(output_dir, "StylizedPlanet.glb")
print("Exporting GLB to:", glb_file)
bpy.ops.export_scene.gltf(
    filepath=glb_file,
    export_format='GLB',
    use_selection=True,
    export_materials='EXPORT',
    export_image_format='AUTO'
)

print("=== PERFECT BAKE COMPLETE ===")
