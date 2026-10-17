"""Generate authentic cyberpunk pixel-art spritesheets for enemies and boss.
Matches the 32x32 retro sci-fi style of the Tech Dungeon pack.
"""
from PIL import Image, ImageDraw

def create_chaser_sheet():
    # 4 frames of 32x32: Scuttling arachnid drone with glowing crimson eye
    sheet = Image.new("RGBA", (128, 32), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        
        # Leg offsets per frame for scuttle animation
        leg_offsets = [
            [(3, 7), (2, 23), (25, 6), (26, 24)],
            [(4, 5), (3, 25), (24, 8), (25, 22)],
            [(2, 8), (4, 22), (26, 5), (24, 25)],
            [(3, 6), (2, 24), (25, 7), (25, 23)]
        ][f]
        
        # Draw articulated legs
        for lx, ly in leg_offsets:
            # Joint from body to foot
            mid_x = (16 + lx) // 2
            mid_y = (16 + ly) // 2 - 2
            d.line([(16, 16), (mid_x, mid_y), (lx, ly)], fill=(35, 40, 58, 255), width=2)
            d.point((lx, ly), fill=(255, 60, 90, 255))
        
        # Chassis shadow
        d.ellipse([9, 10, 23, 24], fill=(20, 24, 38, 255))
        
        # Armored carapace
        d.polygon([(16, 8), (23, 13), (21, 23), (16, 25), (11, 23), (9, 13)], fill=(50, 60, 85, 255), outline=(25, 28, 42, 255))
        d.polygon([(16, 10), (21, 14), (19, 21), (16, 23), (13, 21), (11, 14)], fill=(75, 90, 125, 255))
        
        # Carbon plating highlight
        d.line([(13, 13), (16, 11), (19, 13)], fill=(150, 175, 215, 255), width=1)
        
        # Glowing crimson optical sensor (pulses slightly)
        eye_y = 15 + (1 if f % 2 == 1 else 0)
        d.ellipse([14, eye_y - 2, 18, eye_y + 2], fill=(255, 30, 70, 255))
        d.point((16, eye_y), fill=(255, 230, 240, 255))
        d.point((17, eye_y), fill=(255, 120, 150, 255))
        
        # Micro exhaust heat vents
        d.point((12, 23), fill=(255, 80, 100, 200))
        d.point((20, 23), fill=(255, 80, 100, 200))
        
        sheet.paste(im, (f * 32, 0))
    sheet.save("assets/enemies/chaser_sheet.png")
    print("Saved chaser_sheet.png (128x32)")

def create_shooter_sheet():
    # 4 frames of 32x32: Hovering turret sentry with dual accelerator rails
    sheet = Image.new("RGBA", (128, 32), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        
        bob = 1 if f in [1, 2] else 0
        charge = f == 2
        fire = f == 3
        
        # Thruster hover plume
        plume_h = 4 if not charge else 6
        d.polygon([(14, 25 + bob), (18, 25 + bob), (16, 25 + bob + plume_h)], fill=(255, 170, 30, 220))
        d.point((16, 25 + bob + 1), fill=(255, 240, 180, 255))
        
        # Dual accelerator rail prongs (point forward to the right)
        prong_len = 28 if not fire else 26
        prong_col = (255, 200, 50, 255) if charge else (60, 75, 105, 255)
        d.line([(18, 10 + bob), (prong_len, 10 + bob)], fill=prong_col, width=2)
        d.line([(18, 20 + bob), (prong_len, 20 + bob)], fill=prong_col, width=2)
        
        if charge:
            # Energy gathering arc between rails
            d.line([(prong_len - 4, 10 + bob), (prong_len, 15 + bob), (prong_len - 4, 20 + bob)], fill=(255, 235, 120, 255), width=1)
        if fire:
            # Muzzle flash spark
            d.polygon([(27, 15 + bob), (31, 13 + bob), (29, 15 + bob), (31, 17 + bob)], fill=(255, 250, 220, 255))
        
        # Main chassis (armored hexagonal pod)
        d.polygon([
            (8, 15 + bob), (13, 8 + bob), (20, 8 + bob),
            (22, 15 + bob), (20, 23 + bob), (13, 23 + bob)
        ], fill=(45, 55, 78, 255), outline=(22, 26, 40, 255))
        
        d.polygon([
            (10, 15 + bob), (14, 10 + bob), (19, 10 + bob),
            (20, 15 + bob), (19, 21 + bob), (14, 21 + bob)
        ], fill=(70, 85, 118, 255))
        
        # Amber gyro optical eye
        d.ellipse([13, 12 + bob, 18, 17 + bob], fill=(255, 150, 0, 255))
        d.point((15, 14 + bob), fill=(255, 250, 200, 255))
        d.point((16, 14 + bob), fill=(255, 200, 50, 255))
        
        sheet.paste(im, (f * 32, 0))
    sheet.save("assets/enemies/shooter_sheet.png")
    print("Saved shooter_sheet.png (128x32)")

def create_dasher_sheet():
    # 4 frames of 32x32: Razor interceptor jet with afterburners
    sheet = Image.new("RGBA", (128, 32), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        
        # Frame 0: stalk cruise, Frame 1: cruise bob, Frame 2: telegraph overclock, Frame 3: lunge streak
        is_telegraph = f == 2
        is_lunge = f == 3
        
        # Afterburner exhaust
        burn_len = 10 if is_lunge else (8 if is_telegraph else 5)
        burn_col = (255, 50, 150, 255) if is_telegraph else ((255, 30, 80, 255) if is_lunge else (200, 60, 220, 200))
        d.polygon([(6, 13), (6, 19), (6 - burn_len, 16)], fill=burn_col)
        d.line([(6, 15), (6 - (burn_len // 2), 16)], fill=(255, 220, 255, 255), width=1)
        
        # Delta wing stealth chassis
        body_pts = [(28, 16), (10, 6), (6, 10), (12, 16), (6, 22), (10, 26)]
        chassis_fill = (55, 30, 65, 255) if not is_lunge else (80, 25, 45, 255)
        d.polygon(body_pts, fill=chassis_fill, outline=(25, 15, 32, 255))
        
        # Inner armor plate
        d.polygon([(24, 16), (12, 9), (9, 12), (14, 16), (9, 20), (12, 23)], fill=(95, 45, 115, 255))
        
        # Neon slipstream blade edges
        edge_col = (255, 100, 220, 255) if not is_telegraph else (255, 220, 255, 255)
        d.line([(10, 6), (28, 16)], fill=edge_col, width=1)
        d.line([(10, 26), (28, 16)], fill=edge_col, width=1)
        
        # Cockpit scanner line
        d.line([(16, 16), (22, 16)], fill=(255, 230, 255, 255), width=2)
        d.point((23, 16), fill=(255, 255, 255, 255))
        
        # Wingtip micro beacons
        beacon_col = (255, 40, 120, 255) if not is_lunge else (255, 255, 255, 255)
        d.point((10, 6), fill=beacon_col)
        d.point((10, 26), fill=beacon_col)
        
        sheet.paste(im, (f * 32, 0))
    sheet.save("assets/enemies/dasher_sheet.png")
    print("Saved dasher_sheet.png (128x32)")

def create_boss_sheet():
    # 4 frames of 64x64: Imposing Nexus Overlord core
    sheet = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        
        pulse = (f % 2) * 2
        is_burst = f == 2
        is_dash = f == 3
        
        # Outer kinetic blast ring / shield aura
        aura_rad = 29 if not is_burst else 31
        aura_col = (244, 63, 94, 90 + pulse * 20) if not is_dash else (255, 100, 50, 140)
        d.ellipse([32 - aura_rad, 32 - aura_rad, 32 + aura_rad, 32 + aura_rad], outline=aura_col, width=2)
        
        # Outer heavy armor plating segments (8 articulated facets)
        outer_pts = [
            (32, 5), (49, 12), (59, 28), (56, 46),
            (42, 58), (22, 58), (8, 46), (5, 28), (15, 12)
        ]
        d.polygon(outer_pts, fill=(35, 18, 30, 255), outline=(15, 8, 16, 255))
        
        # Intermediate mechanical casing
        mid_pts = [
            (32, 10), (45, 16), (53, 29), (50, 43),
            (39, 53), (25, 53), (14, 43), (11, 29), (19, 16)
        ]
        d.polygon(mid_pts, fill=(65, 28, 48, 255), outline=(40, 15, 30, 255))
        
        # Neon circuit conduits radiating inward
        conduit_col = (255, 70, 110, 255) if not is_burst else (255, 220, 230, 255)
        for (cx, cy) in [(32, 12), (48, 20), (51, 38), (38, 50), (26, 50), (13, 38), (16, 20)]:
            d.line([(cx, cy), (32, 32)], fill=conduit_col, width=2)
            d.point((cx, cy), fill=(255, 230, 240, 255))
        
        # Heavy central core housing
        d.ellipse([21, 21, 43, 43], fill=(20, 6, 14, 255), outline=(180, 30, 60, 255), width=2)
        
        # Pulsing singularity heart
        core_r = 8 + pulse if not is_burst else 11
        core_col = (244, 63, 94, 255) if not is_burst else (255, 180, 200, 255)
        d.ellipse([32 - core_r, 32 - core_r, 32 + core_r, 32 + core_r], fill=core_col)
        d.ellipse([30, 30, 34, 34], fill=(255, 255, 255, 255))
        
        sheet.paste(im, (f * 64, 0))
    sheet.save("assets/enemies/boss_sheet.png")
    print("Saved boss_sheet.png (256x64)")

def create_boss_drone():
    # 16x16 orbital defense drone
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([2, 2, 13, 13], fill=(50, 20, 38, 255), outline=(244, 63, 94, 255), width=1)
    d.ellipse([5, 5, 10, 10], fill=(255, 80, 120, 255))
    d.point((7, 7), fill=(255, 240, 245, 255))
    im.save("assets/enemies/boss_drone.png")
    print("Saved boss_drone.png (16x16)")

if __name__ == "__main__":
    create_chaser_sheet()
    create_shooter_sheet()
    create_dasher_sheet()
    create_boss_sheet()
    create_boss_drone()
    print("All enemy pixel art successfully generated!")
