import bpy
import os

print("=== STARTING PLANET BAKE SCRIPT ===")

planet_blend = r"C:\Users\MyBook Hype AMD\Documents\Spacesky\assets\Planet\Futuristic Stylized Ringed Planet.blend"
output_dir = r"C:\Users\MyBook Hype AMD\Documents\Spacesky\assets\Planet"
os.makedirs(output_dir, exist_ok=True)

# Set render engine to Cycles for baking
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 16
scene.cycles.bake_type = 'DIFFUSE'
scene.render.bake.use_pass_direct = False
scene.render.bake.use_pass_indirect = False
scene.render.bake.use_pass_color = True

# -------------------------------------------------------------
# 1. BAKE PLANET (Icosphere)
# -------------------------------------------------------------
planet_obj = bpy.data.objects.get("Icosphere")
if planet_obj:
    print("Found Planet object: Icosphere")
    bpy.context.view_layer.objects.active = planet_obj
    planet_obj.select_set(True)
    
    mat = planet_obj.active_material
    nodes = mat.node_tree.nodes
    
    # Create image for Albedo
    tex_img = bpy.data.images.new("planet_albedo", width=2048, height=2048, alpha=False)
    img_node = nodes.new('ShaderNodeTexImage')
    img_node.image = tex_img
    nodes.active = img_node
    
    print("Baking planet albedo...")
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})
    
    albedo_path = os.path.join(output_dir, "planet_albedo.png")
    tex_img.filepath_raw = albedo_path
    tex_img.file_format = 'PNG'
    tex_img.save()
    print("Saved planet albedo to:", albedo_path)
    
    # Bake Normal
    print("Baking planet normal...")
    tex_norm = bpy.data.images.new("planet_normal", width=2048, height=2048, alpha=False)
    img_node.image = tex_norm
    bpy.ops.object.bake(type='NORMAL')
    
    norm_path = os.path.join(output_dir, "planet_normal.png")
    tex_norm.filepath_raw = norm_path
    tex_norm.file_format = 'PNG'
    tex_norm.save()
    print("Saved planet normal to:", norm_path)

# -------------------------------------------------------------
# 2. BAKE RINGS (Circle)
# -------------------------------------------------------------
rings_obj = bpy.data.objects.get("Circle")
if rings_obj:
    print("Found Rings object: Circle")
    bpy.context.view_layer.objects.active = rings_obj
    rings_obj.select_set(True)
    
    mat_rings = rings_obj.active_material
    r_nodes = mat_rings.node_tree.nodes
    
    # Find Emission color and Alpha factor
    em_node = r_nodes.get("Emission")
    mix_node = r_nodes.get("Mix.001")
    
    # Temporary Principled BSDF to bake cleanly
    temp_bsdf = r_nodes.new('ShaderNodeBsdfPrincipled')
    if em_node and em_node.inputs['Color'].is_linked:
        mat_rings.node_tree.links.new(em_node.inputs['Color'].links[0].from_socket, temp_bsdf.inputs['Base Color'])
    
    if mix_node and mix_node.outputs[0].is_linked:
        # mix_node controls transparency factor
        mat_rings.node_tree.links.new(mix_node.outputs[0], temp_bsdf.inputs['Alpha'])
    
    out_node = next((n for n in r_nodes if n.type == 'OUTPUT_MATERIAL'), None)
    mat_rings.node_tree.links.new(temp_bsdf.outputs['BSDF'], out_node.inputs['Surface'])
    
    tex_rings = bpy.data.images.new("rings_albedo", width=2048, height=2048, alpha=True)
    r_img_node = r_nodes.new('ShaderNodeTexImage')
    r_img_node.image = tex_rings
    r_nodes.active = r_img_node
    
    print("Baking rings albedo...")
    # Bake Emit or Diffuse
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})
    
    rings_path = os.path.join(output_dir, "rings_albedo.png")
    tex_rings.filepath_raw = rings_path
    tex_rings.file_format = 'PNG'
    tex_rings.save()
    print("Saved rings albedo to:", rings_path)

# -------------------------------------------------------------
# 3. BUILD CLEAN EXPORT MATERIALS & EXPORT GLB
# -------------------------------------------------------------
print("Configuring clean PBR materials for GLB export...")

# Clean Planet Material
if planet_obj:
    clean_p_mat = bpy.data.materials.new("Planet_Baked")
    clean_p_mat.use_nodes = True
    p_tree = clean_p_mat.node_tree
    p_tree.nodes.clear()
    
    p_out = p_tree.nodes.new('ShaderNodeOutputMaterial')
    p_bsdf = p_tree.nodes.new('ShaderNodeBsdfPrincipled')
    p_tree.links.new(p_bsdf.outputs['BSDF'], p_out.inputs['Surface'])
    
    p_img = p_tree.nodes.new('ShaderNodeTexImage')
    p_img.image = bpy.data.images.load(os.path.join(output_dir, "planet_albedo.png"))
    p_tree.links.new(p_img.outputs['Color'], p_bsdf.inputs['Base Color'])
    
    p_norm_img = p_tree.nodes.new('ShaderNodeTexImage')
    p_norm_img.image = bpy.data.images.load(os.path.join(output_dir, "planet_normal.png"))
    p_norm_img.image.colorspace_settings.name = 'Non-Color'
    p_norm_map = p_tree.nodes.new('ShaderNodeNormalMap')
    p_tree.links.new(p_norm_img.outputs['Color'], p_norm_map.inputs['Color'])
    p_tree.links.new(p_norm_map.outputs['Normal'], p_bsdf.inputs['Normal'])
    
    planet_obj.data.materials.clear()
    planet_obj.data.materials.append(clean_p_mat)

# Clean Rings Material
if rings_obj:
    clean_r_mat = bpy.data.materials.new("Rings_Baked")
    clean_r_mat.use_nodes = True
    clean_r_mat.blend_method = 'BLEND'
    r_tree = clean_r_mat.node_tree
    r_tree.nodes.clear()
    
    r_out = r_tree.nodes.new('ShaderNodeOutputMaterial')
    r_bsdf = r_tree.nodes.new('ShaderNodeBsdfPrincipled')
    r_tree.links.new(r_bsdf.outputs['BSDF'], r_out.inputs['Surface'])
    
    r_img = r_tree.nodes.new('ShaderNodeTexImage')
    r_img.image = bpy.data.images.load(os.path.join(output_dir, "rings_albedo.png"))
    r_tree.links.new(r_img.outputs['Color'], r_bsdf.inputs['Base Color'])
    r_tree.links.new(r_img.outputs['Color'], r_bsdf.inputs['Emission Color'])
    r_bsdf.inputs['Emission Strength'].default_value = 1.5
    
    rings_obj.data.materials.clear()
    rings_obj.data.materials.append(clean_r_mat)

# Select only Planet and Rings for export
bpy.ops.object.select_all(action='DESELECT')
if planet_obj:
    planet_obj.select_set(True)
if rings_obj:
    rings_obj.select_set(True)

glb_path = os.path.join(output_dir, "StylizedPlanet.glb")
print("Exporting GLB to:", glb_path)
bpy.ops.export_scene.gltf(
    filepath=glb_path,
    export_format='GLB',
    use_selection=True,
    export_materials='EXPORT',
    export_image_format='AUTO'
)
print("=== BAKE & EXPORT COMPLETED SUCCESSFULLY ===")
