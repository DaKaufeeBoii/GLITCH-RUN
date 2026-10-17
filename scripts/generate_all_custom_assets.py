"""Unified asset generator for GLITCH//RUN.
Generates 100% custom, original cyberpunk pixel-art assets:
- Player (idle, run, dash, hurt, death) and Blaster weapon
- Environment tileset (floor plates, circuit panels, vents, hatches, server racks, barriers)
- UI (energy heart modules: full and depleted)
- Enemies (Chaser, Shooter, Dasher, Boss, Boss Drone)
- Weapons (Plasma bolt, Tachyon hazard orb)
"""
import os
from PIL import Image, ImageDraw

def ensure_dirs():
    os.makedirs("assets/player", exist_ok=True)
    os.makedirs("assets/environment", exist_ok=True)
    os.makedirs("assets/ui", exist_ok=True)
    os.makedirs("assets/enemies", exist_ok=True)
    os.makedirs("assets/weapons", exist_ok=True)

# -------------------------------------------------------------
# 1. PLAYER SPRITESHEET (192 x 160: 6 cols x 5 rows of 32x32)
# -------------------------------------------------------------
def create_player_assets():
    sheet = Image.new("RGBA", (192, 160), (0, 0, 0, 0))
    
    # Base palette
    c_dark = (22, 26, 38, 255)
    c_armor = (38, 48, 70, 255)
    c_armor_light = (62, 78, 110, 255)
    c_suit = (28, 34, 48, 255)
    c_cyan_glow = (56, 189, 248, 255)
    c_cyan_bright = (224, 242, 254, 255)
    c_white = (255, 255, 255, 255)
    
    # Helper to draw operative base
    def draw_operative(d, ox, oy, leg_l, leg_r, body_y, head_y, arm_angle=0, glow=True, hurt=False, dead=False):
        if dead:
            # Crumpled / collapsing operative
            d.ellipse([ox + 6, oy + 22, ox + 26, oy + 30], fill=(20, 24, 34, 255))
            d.polygon([(ox + 8, oy + 24), (ox + 22, oy + 20), (ox + 24, oy + 28)], fill=c_armor)
            d.ellipse([ox + 20, oy + 19, ox + 26, oy + 25], fill=c_suit)
            d.point((ox + 23, oy + 22), fill=(100, 120, 140, 255))
            return
            
        color_shift = (240, 240, 255, 255) if not hurt else (255, 120, 140, 255)
        
        # Shadow beneath
        d.ellipse([ox + 10, oy + 26, ox + 22, oy + 31], fill=(12, 16, 24, 180))
        
        # Legs
        # Left leg
        d.line([(ox + 13, oy + 18 + body_y), (ox + 12 + leg_l[0], oy + 24 + leg_l[1]), (ox + 11 + leg_l[0], oy + 29 + leg_l[1])], fill=c_suit, width=2)
        d.rectangle([ox + 10 + leg_l[0], oy + 28 + leg_l[1], ox + 13 + leg_l[0], oy + 30 + leg_l[1]], fill=c_dark)
        # Right leg
        d.line([(ox + 19, oy + 18 + body_y), (ox + 20 + leg_r[0], oy + 24 + leg_r[1]), (ox + 21 + leg_r[0], oy + 29 + leg_r[1])], fill=c_suit, width=2)
        d.rectangle([ox + 19 + leg_r[0], oy + 28 + leg_r[1], ox + 22 + leg_r[0], oy + 30 + leg_r[1]], fill=c_dark)
        
        # Torso / Armor vest
        d.polygon([
            (ox + 12, oy + 12 + body_y), (ox + 20, oy + 12 + body_y),
            (ox + 21, oy + 19 + body_y), (ox + 11, oy + 19 + body_y)
        ], fill=c_armor, outline=c_dark)
        d.rectangle([ox + 14, oy + 14 + body_y, ox + 18, oy + 18 + body_y], fill=c_armor_light)
        
        # Cyber energy core on chest
        if glow:
            d.point((ox + 16, oy + 16 + body_y), fill=c_cyan_bright)
            d.point((ox + 15, oy + 16 + body_y), fill=c_cyan_glow)
            d.point((ox + 17, oy + 16 + body_y), fill=c_cyan_glow)
            
        # Helmet / Head
        d.ellipse([ox + 12, oy + 5 + head_y, ox + 20, oy + 13 + head_y], fill=c_dark)
        d.rectangle([ox + 13, oy + 6 + head_y, ox + 19, oy + 11 + head_y], fill=c_armor)
        # Cyan visor line
        d.line([(ox + 15, oy + 8 + head_y), (ox + 20, oy + 8 + head_y)], fill=c_cyan_glow if glow else (100, 110, 130, 255), width=1)
        d.point((ox + 19, oy + 8 + head_y), fill=c_cyan_bright if glow else (150, 160, 180, 255))
        
        # Tactical shoulder pauldron
        d.rectangle([ox + 11, oy + 12 + body_y, ox + 13, oy + 15 + body_y], fill=c_armor_light)
        d.rectangle([ox + 19, oy + 12 + body_y, ox + 21, oy + 15 + body_y], fill=c_armor_light)

    # Row 0: Idle (4 frames)
    for f in range(4):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        bob = 1 if f in [1, 2] else 0
        draw_operative(d, 0, 0, (0, 0), (0, 0), bob, bob)
        sheet.paste(im, (f * 32, 0 * 32))
        
    # Row 1: Run (6 frames)
    run_offsets = [
        ((-2, -1), (2, 0), 0, 0),
        ((-3, -2), (3, -1), -1, -1),
        ((-1, 0), (1, -2), 0, 0),
        ((2, 0), (-2, -1), 0, 0),
        ((3, -1), (-3, -2), -1, -1),
        ((1, -2), (-1, 0), 0, 0)
    ]
    for f in range(6):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        lo, ro, by, hy = run_offsets[f]
        draw_operative(d, 0, 0, lo, ro, by, hy)
        sheet.paste(im, (f * 32, 1 * 32))
        
    # Row 2: Dash (4 frames)
    for f in range(4):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # Low forward slide with thrust trail
        slide_x = f * 2
        d.line([(4, 20), (12 + slide_x, 20)], fill=(56, 189, 248, 160), width=2)
        draw_operative(d, 4 + slide_x, 3, (-4, -2), (4, -1), 2, 2)
        sheet.paste(im, (f * 32, 2 * 32))
        
    # Row 3: Hurt (4 frames)
    for f in range(4):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        recoil_x = -f if f < 2 else -(4 - f)
        draw_operative(d, recoil_x, 0, (-1, 0), (1, 0), 0, -1, hurt=True)
        sheet.paste(im, (f * 32, 3 * 32))
        
    # Row 4: Death (6 frames)
    for f in range(6):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        if f < 3:
            draw_operative(d, -f, f * 2, (-1, 0), (1, 0), f, f, glow=False, hurt=True)
        else:
            draw_operative(d, 0, 0, (0, 0), (0, 0), 0, 0, dead=True)
            # Sparks
            if f < 5:
                d.point((16 + f, 20 - f), fill=(56, 189, 248, 255))
                d.point((20 - f, 22), fill=(255, 100, 100, 255))
        sheet.paste(im, (f * 32, 4 * 32))

    sheet.save("assets/player/player_sheet.png")
    print("Saved assets/player/player_sheet.png (192x160)")
    
    # Blaster weapon (32x32)
    blaster = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(blaster)
    # Gun receiver & barrel
    d.rectangle([10, 12, 24, 16], fill=c_dark)
    d.rectangle([11, 13, 23, 15], fill=c_armor)
    # Energy rail top channel
    d.line([(14, 12), (24, 12)], fill=c_cyan_glow, width=1)
    d.point((24, 12), fill=c_white)
    # Pistol grip
    d.polygon([(12, 16), (15, 16), (14, 21), (11, 21)], fill=c_dark)
    # Muzzle emitter ring
    d.rectangle([23, 13, 25, 15], fill=c_armor_light)
    d.point((25, 14), fill=c_cyan_bright)
    blaster.save("assets/player/blaster.png")
    print("Saved assets/player/blaster.png (32x32)")

# -------------------------------------------------------------
# 2. ENVIRONMENT TILESET (256 x 128: 8 cols x 4 rows of 32x32)
# -------------------------------------------------------------
def create_environment_tileset():
    tileset = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
    
    # Base tech tile colors
    c_plate_base = (30, 36, 50, 255)
    c_plate_light = (42, 50, 68, 255)
    c_plate_dark = (20, 24, 34, 255)
    c_groove = (14, 17, 24, 255)
    c_cyan_dim = (20, 100, 140, 255)
    c_cyan_bright = (56, 189, 248, 255)
    
    # Tile (0, 0): Standard tech floor plate
    t0 = Image.new("RGBA", (32, 32), c_plate_base)
    d0 = ImageDraw.Draw(t0)
    d0.rectangle([0, 0, 31, 31], outline=c_groove, width=1)
    d0.rectangle([1, 1, 30, 30], outline=c_plate_light, width=1)
    # Corner rivets
    for (rx, ry) in [(3, 3), (28, 3), (3, 28), (28, 28)]:
        d0.point((rx, ry), fill=c_groove)
        d0.point((rx, ry - 1), fill=c_plate_light)
    tileset.paste(t0, (0 * 32, 0 * 32))
    
    # Tile (1, 0): Circuit conduit floor plate
    t1 = t0.copy()
    d1 = ImageDraw.Draw(t1)
    # Cyan circuit traces
    d1.line([(16, 0), (16, 12), (24, 12), (24, 31)], fill=c_cyan_dim, width=1)
    d1.line([(8, 16), (16, 16)], fill=c_cyan_dim, width=1)
    d1.rectangle([15, 11, 17, 13], fill=c_cyan_bright)
    tileset.paste(t1, (1 * 32, 0 * 32))
    
    # Tile (2, 0): Heavy ventilation grate
    t2 = t0.copy()
    d2 = ImageDraw.Draw(t2)
    d2.rectangle([4, 4, 27, 27], fill=c_groove)
    for gy in range(6, 26, 3):
        d2.line([(6, gy), (25, gy)], fill=c_plate_light, width=1)
    tileset.paste(t2, (2 * 32, 0 * 32))
    
    # Tile (3, 0): Sub-floor access hatch with hazard trim
    t3 = t0.copy()
    d3 = ImageDraw.Draw(t3)
    d3.rectangle([4, 4, 27, 27], fill=c_plate_dark, outline=c_groove)
    # Angled yellow/black hazard striping on top & bottom edge
    for hx in range(4, 26, 4):
        d3.line([(hx, 5), (hx + 2, 5)], fill=(234, 179, 8, 255), width=1)
        d3.line([(hx, 26), (hx + 2, 26)], fill=(234, 179, 8, 255), width=1)
    d3.rectangle([14, 14, 17, 17], fill=c_plate_light)
    tileset.paste(t3, (3 * 32, 0 * 32))
    
    # Tile (0, 1): Reinforced wall block
    tw0 = Image.new("RGBA", (32, 32), (18, 22, 32, 255))
    dw0 = ImageDraw.Draw(tw0)
    dw0.rectangle([0, 0, 31, 31], outline=(10, 12, 18, 255), width=1)
    dw0.rectangle([3, 3, 28, 28], fill=(28, 34, 48, 255), outline=(42, 52, 72, 255))
    # Structural bevel cross
    dw0.line([(3, 3), (28, 28)], fill=(20, 24, 34, 255), width=1)
    dw0.line([(3, 28), (28, 3)], fill=(20, 24, 34, 255), width=1)
    tileset.paste(tw0, (0 * 32, 1 * 32))
    
    # Tile (1, 1): Wall with glowing cyber conduit
    tw1 = tw0.copy()
    dw1 = ImageDraw.Draw(tw1)
    dw1.rectangle([14, 0, 17, 31], fill=(12, 16, 24, 255))
    dw1.line([(15, 0), (15, 31)], fill=c_cyan_bright, width=1)
    tileset.paste(tw1, (1 * 32, 1 * 32))
    
    # Tile (0, 2): Mainframe server rack (Obstacle tile)
    ts0 = Image.new("RGBA", (32, 32), (16, 20, 30, 255))
    ds0 = ImageDraw.Draw(ts0)
    ds0.rectangle([0, 0, 31, 31], outline=(10, 12, 18, 255), width=1)
    # Server bays
    for sy in range(3, 28, 6):
        ds0.rectangle([3, sy, 28, sy + 4], fill=(26, 32, 46, 255), outline=(38, 48, 68, 255))
        # Telemetry LED lights
        ds0.point((5, sy + 2), fill=(34, 197, 94, 255)) # Green
        ds0.point((7, sy + 2), fill=(56, 189, 248, 255)) # Cyan
        ds0.point((9, sy + 2), fill=(244, 63, 94, 255)) # Red
        # Heat exhaust louvers
        for lx in range(13, 27, 2):
            ds0.point((lx, sy + 2), fill=(14, 17, 24, 255))
    tileset.paste(ts0, (0 * 32, 2 * 32))
    
    # Tile (1, 2): Power generator terminal
    ts1 = Image.new("RGBA", (32, 32), (16, 20, 30, 255))
    ds1 = ImageDraw.Draw(ts1)
    ds1.rectangle([0, 0, 31, 31], outline=(10, 12, 18, 255), width=1)
    # Coil core
    ds1.ellipse([6, 6, 25, 25], fill=(26, 32, 46, 255), outline=(56, 189, 248, 255), width=1)
    ds1.ellipse([10, 10, 21, 21], fill=(56, 189, 248, 200))
    ds1.point((16, 16), fill=(255, 255, 255, 255))
    tileset.paste(ts1, (1 * 32, 2 * 32))

    tileset.save("assets/environment/tileset.png")
    print("Saved assets/environment/tileset.png (256x128)")

# -------------------------------------------------------------
# 3. UI HEARTS (64 x 32: two 32x32 cells: Full & Empty)
# -------------------------------------------------------------
def create_ui_assets():
    hearts = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    
    # Full Heart (Cell 0: 0..31)
    h_full = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d0 = ImageDraw.Draw(h_full)
    # Dark outer carbon housing
    d0.polygon([
        (16, 26), (6, 16), (6, 10), (10, 6), (16, 11), (22, 6), (26, 10), (26, 16)
    ], fill=(22, 26, 38, 255), outline=(12, 15, 22, 255))
    # Glowing ruby heart core
    d0.polygon([
        (16, 24), (8, 15), (8, 11), (11, 8), (16, 13), (21, 8), (24, 11), (24, 15)
    ], fill=(244, 63, 94, 255))
    # Vibrant highlight
    d0.polygon([
        (16, 22), (9, 14), (9, 12), (12, 9), (16, 13)
    ], fill=(251, 113, 133, 255))
    # Specular glint
    d0.rectangle([10, 10, 12, 11], fill=(255, 255, 255, 255))
    hearts.paste(h_full, (0, 0))
    
    # Empty Heart (Cell 1: 32..63)
    h_empty = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d1 = ImageDraw.Draw(h_empty)
    # Dark depleted chassis
    d1.polygon([
        (16, 26), (6, 16), (6, 10), (10, 6), (16, 11), (22, 6), (26, 10), (26, 16)
    ], fill=(22, 26, 38, 255), outline=(12, 15, 22, 255))
    # Depleted inner hollow
    d1.polygon([
        (16, 24), (8, 15), (8, 11), (11, 8), (16, 13), (21, 8), (24, 11), (24, 15)
    ], fill=(16, 19, 28, 255), outline=(38, 48, 68, 255))
    # Faint red emergency indicator dot
    d1.point((16, 16), fill=(159, 18, 57, 180))
    hearts.paste(h_empty, (32, 0))
    
    hearts.save("assets/ui/hearts.png")
    print("Saved assets/ui/hearts.png (64x32)")

# -------------------------------------------------------------
# 4. WEAPONS (Plasma Bolt & Tachyon Orb)
# -------------------------------------------------------------
def create_weapon_assets():
    # 1. Player plasma bolt (32x16)
    bolt = Image.new("RGBA", (32, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(bolt)
    d.ellipse([2, 4, 28, 12], fill=(56, 189, 248, 140))
    d.ellipse([8, 5, 29, 11], fill=(14, 165, 233, 230))
    d.ellipse([14, 6, 30, 10], fill=(224, 242, 254, 255))
    d.ellipse([20, 7, 30, 9], fill=(255, 255, 255, 255))
    bolt.save("assets/weapons/player_plasma.png")
    
    # 2. Enemy tachyon orb (24x24)
    tachyon = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(tachyon)
    d.ellipse([1, 1, 23, 23], fill=(244, 63, 94, 90), outline=(255, 70, 110, 180), width=1)
    d.ellipse([4, 4, 20, 20], fill=(225, 29, 72, 210))
    d.ellipse([7, 7, 17, 17], fill=(253, 164, 175, 255))
    d.ellipse([9, 9, 15, 15], fill=(255, 255, 255, 255))
    tachyon.save("assets/weapons/enemy_tachyon.png")
    print("Saved weapon assets!")

# -------------------------------------------------------------
# 5. ENEMIES & BOSS (Chaser, Shooter, Dasher, Boss, Drone)
# -------------------------------------------------------------
def create_enemy_assets():
    # Chaser (128x32: 4 frames)
    chaser_sheet = Image.new("RGBA", (128, 32), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        leg_offsets = [
            [(3, 7), (2, 23), (25, 6), (26, 24)],
            [(4, 5), (3, 25), (24, 8), (25, 22)],
            [(2, 8), (4, 22), (26, 5), (24, 25)],
            [(3, 6), (2, 24), (25, 7), (25, 23)]
        ][f]
        for lx, ly in leg_offsets:
            mid_x = (16 + lx) // 2
            mid_y = (16 + ly) // 2 - 2
            d.line([(16, 16), (mid_x, mid_y), (lx, ly)], fill=(35, 40, 58, 255), width=2)
            d.point((lx, ly), fill=(255, 60, 90, 255))
        d.ellipse([9, 10, 23, 24], fill=(20, 24, 38, 255))
        d.polygon([(16, 8), (23, 13), (21, 23), (16, 25), (11, 23), (9, 13)], fill=(50, 60, 85, 255), outline=(25, 28, 42, 255))
        d.polygon([(16, 10), (21, 14), (19, 21), (16, 23), (13, 21), (11, 14)], fill=(75, 90, 125, 255))
        d.line([(13, 13), (16, 11), (19, 13)], fill=(150, 175, 215, 255), width=1)
        eye_y = 15 + (1 if f % 2 == 1 else 0)
        d.ellipse([14, eye_y - 2, 18, eye_y + 2], fill=(255, 30, 70, 255))
        d.point((16, eye_y), fill=(255, 230, 240, 255))
        d.point((17, eye_y), fill=(255, 120, 150, 255))
        chaser_sheet.paste(im, (f * 32, 0))
    chaser_sheet.save("assets/enemies/chaser_sheet.png")

    # Shooter (128x32: 4 frames)
    shooter_sheet = Image.new("RGBA", (128, 32), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        bob = 1 if f in [1, 2] else 0
        charge = f == 2
        fire = f == 3
        plume_h = 4 if not charge else 6
        d.polygon([(14, 25 + bob), (18, 25 + bob), (16, 25 + bob + plume_h)], fill=(255, 170, 30, 220))
        d.point((16, 25 + bob + 1), fill=(255, 240, 180, 255))
        prong_len = 28 if not fire else 26
        prong_col = (255, 200, 50, 255) if charge else (60, 75, 105, 255)
        d.line([(18, 10 + bob), (prong_len, 10 + bob)], fill=prong_col, width=2)
        d.line([(18, 20 + bob), (prong_len, 20 + bob)], fill=prong_col, width=2)
        if charge:
            d.line([(prong_len - 4, 10 + bob), (prong_len, 15 + bob), (prong_len - 4, 20 + bob)], fill=(255, 235, 120, 255), width=1)
        if fire:
            d.polygon([(27, 15 + bob), (31, 13 + bob), (29, 15 + bob), (31, 17 + bob)], fill=(255, 250, 220, 255))
        d.polygon([(8, 15 + bob), (13, 8 + bob), (20, 8 + bob), (22, 15 + bob), (20, 23 + bob), (13, 23 + bob)], fill=(45, 55, 78, 255), outline=(22, 26, 40, 255))
        d.polygon([(10, 15 + bob), (14, 10 + bob), (19, 10 + bob), (20, 15 + bob), (19, 21 + bob), (14, 21 + bob)], fill=(70, 85, 118, 255))
        d.ellipse([13, 12 + bob, 18, 17 + bob], fill=(255, 150, 0, 255))
        d.point((15, 14 + bob), fill=(255, 250, 200, 255))
        shooter_sheet.paste(im, (f * 32, 0))
    shooter_sheet.save("assets/enemies/shooter_sheet.png")

    # Dasher (128x32: 4 frames)
    dasher_sheet = Image.new("RGBA", (128, 32), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        is_telegraph = f == 2
        is_lunge = f == 3
        burn_len = 10 if is_lunge else (8 if is_telegraph else 5)
        burn_col = (255, 50, 150, 255) if is_telegraph else ((255, 30, 80, 255) if is_lunge else (200, 60, 220, 200))
        d.polygon([(6, 13), (6, 19), (6 - burn_len, 16)], fill=burn_col)
        d.line([(6, 15), (6 - (burn_len // 2), 16)], fill=(255, 220, 255, 255), width=1)
        body_pts = [(28, 16), (10, 6), (6, 10), (12, 16), (6, 22), (10, 26)]
        chassis_fill = (55, 30, 65, 255) if not is_lunge else (80, 25, 45, 255)
        d.polygon(body_pts, fill=chassis_fill, outline=(25, 15, 32, 255))
        d.polygon([(24, 16), (12, 9), (9, 12), (14, 16), (9, 20), (12, 23)], fill=(95, 45, 115, 255))
        edge_col = (255, 100, 220, 255) if not is_telegraph else (255, 220, 255, 255)
        d.line([(10, 6), (28, 16)], fill=edge_col, width=1)
        d.line([(10, 26), (28, 16)], fill=edge_col, width=1)
        d.line([(16, 16), (22, 16)], fill=(255, 230, 255, 255), width=2)
        d.point((23, 16), fill=(255, 255, 255, 255))
        dasher_sheet.paste(im, (f * 32, 0))
    dasher_sheet.save("assets/enemies/dasher_sheet.png")

    # Boss (256x64: 4 frames)
    boss_sheet = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        pulse = (f % 2) * 2
        is_burst = f == 2
        is_dash = f == 3
        aura_rad = 29 if not is_burst else 31
        aura_col = (244, 63, 94, 90 + pulse * 20) if not is_dash else (255, 100, 50, 140)
        d.ellipse([32 - aura_rad, 32 - aura_rad, 32 + aura_rad, 32 + aura_rad], outline=aura_col, width=2)
        outer_pts = [(32, 5), (49, 12), (59, 28), (56, 46), (42, 58), (22, 58), (8, 46), (5, 28), (15, 12)]
        d.polygon(outer_pts, fill=(35, 18, 30, 255), outline=(15, 8, 16, 255))
        mid_pts = [(32, 10), (45, 16), (53, 29), (50, 43), (39, 53), (25, 53), (14, 43), (11, 29), (19, 16)]
        d.polygon(mid_pts, fill=(65, 28, 48, 255), outline=(40, 15, 30, 255))
        conduit_col = (255, 70, 110, 255) if not is_burst else (255, 220, 230, 255)
        for (cx, cy) in [(32, 12), (48, 20), (51, 38), (38, 50), (26, 50), (13, 38), (16, 20)]:
            d.line([(cx, cy), (32, 32)], fill=conduit_col, width=2)
            d.point((cx, cy), fill=(255, 230, 240, 255))
        d.ellipse([21, 21, 43, 43], fill=(20, 6, 14, 255), outline=(180, 30, 60, 255), width=2)
        core_r = 8 + pulse if not is_burst else 11
        core_col = (244, 63, 94, 255) if not is_burst else (255, 180, 200, 255)
        d.ellipse([32 - core_r, 32 - core_r, 32 + core_r, 32 + core_r], fill=core_col)
        d.ellipse([30, 30, 34, 34], fill=(255, 255, 255, 255))
        boss_sheet.paste(im, (f * 64, 0))
    boss_sheet.save("assets/enemies/boss_sheet.png")

    # Boss Drone (16x16)
    drone = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(drone)
    d.ellipse([2, 2, 13, 13], fill=(50, 20, 38, 255), outline=(244, 63, 94, 255), width=1)
    d.ellipse([5, 5, 10, 10], fill=(255, 80, 120, 255))
    d.point((7, 7), fill=(255, 240, 245, 255))
    drone.save("assets/enemies/boss_drone.png")
    print("Saved all enemy assets!")

if __name__ == "__main__":
    ensure_dirs()
    create_player_assets()
    create_environment_tileset()
    create_ui_assets()
    create_weapon_assets()
    create_enemy_assets()
    print("=== All custom assets generated successfully! ===")
