"""Generates clean placeholder assets using basic geometrical shapes for GLITCH//RUN.
Shapes used:
- Triangles / Arrows (Player)
- Diamonds (Chasers, UI Heart Gems)
- Hexagons (Shooters)
- Chevrons (Dashers)
- Octagons & Concentric Rings (Boss)
- Circles / Spheres (Weapon Projectiles & Cores)
- Rectangles & Grid lines (Environment tiles)
"""
import os
import math
from PIL import Image, ImageDraw

def ensure_dirs():
    os.makedirs("assets/player", exist_ok=True)
    os.makedirs("assets/environment", exist_ok=True)
    os.makedirs("assets/ui", exist_ok=True)
    os.makedirs("assets/enemies", exist_ok=True)
    os.makedirs("assets/weapons", exist_ok=True)

def create_ui_hearts():
    im = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # 1. Full Heart Gem (0..31): Geometric faceted ruby diamond
    # Outer dark bracket
    d.polygon([(16, 28), (5, 17), (5, 9), (11, 4), (16, 8), (21, 4), (27, 9), (27, 17)], fill=(15, 23, 42, 255), outline=(30, 41, 59, 255))
    # Ruby facet core
    d.polygon([(16, 26), (7, 16), (7, 10), (12, 6), (16, 9), (20, 6), (25, 10), (25, 16)], fill=(244, 63, 94, 255))
    # Bright facet highlight
    d.polygon([(16, 24), (8, 15), (8, 11), (12, 7), (16, 10)], fill=(251, 113, 133, 255))
    # Specular glint
    d.rectangle([10, 9, 13, 11], fill=(255, 255, 255, 255))

    # 2. Empty Heart Gem (32..63): Depleted geometric bracket
    ox = 32
    d.polygon([(ox + 16, 28), (ox + 5, 17), (ox + 5, 9), (ox + 11, 4), (ox + 16, 8), (ox + 21, 4), (ox + 27, 9), (ox + 27, 17)], fill=(15, 23, 42, 255), outline=(51, 65, 85, 255))
    d.polygon([(ox + 16, 26), (ox + 7, 16), (ox + 7, 10), (ox + 12, 6), (ox + 16, 9), (ox + 20, 6), (ox + 25, 10), (ox + 25, 16)], fill=(30, 41, 59, 255))
    d.point((ox + 16, 16), fill=(136, 19, 55, 255))

    im.save("assets/ui/hearts.png")
    print("Saved assets/ui/hearts.png")

def create_weapon_assets():
    # 1. Player plasma bolt (32x16) - clean geometric capsule & circle glow
    bolt = Image.new("RGBA", (32, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(bolt)
    # Cyan outer energy capsule
    d.rounded_rectangle([2, 3, 29, 12], radius=4, fill=(56, 189, 248, 160))
    # Inner bright cyan core
    d.rounded_rectangle([8, 5, 28, 10], radius=3, fill=(14, 165, 233, 240))
    # White hot center point
    d.ellipse([18, 6, 26, 9], fill=(255, 255, 255, 255))
    bolt.save("assets/weapons/player_plasma.png")

    # 2. Hostile enemy tachyon orb (24x24) - concentric geometric circles
    tachyon = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(tachyon)
    d2.ellipse([1, 1, 22, 22], fill=(244, 63, 94, 90), outline=(251, 113, 133, 180), width=1)
    d2.ellipse([4, 4, 19, 19], fill=(225, 29, 72, 220))
    d2.ellipse([7, 7, 16, 16], fill=(253, 164, 175, 255))
    d2.ellipse([9, 9, 14, 14], fill=(255, 255, 255, 255))
    tachyon.save("assets/weapons/enemy_tachyon.png")
    print("Saved weapon placeholder assets!")

def create_environment_assets():
    # Minimal geometric grid tileset (128x64)
    tiles = Image.new("RGBA", (128, 64), (11, 15, 25, 255))
    d = ImageDraw.Draw(tiles)
    # Tile 0: Standard geometric plate with subtle border
    d.rectangle([0, 0, 31, 31], outline=(30, 41, 59, 255), width=1)
    d.rectangle([2, 2, 29, 29], outline=(15, 23, 42, 255), width=1)
    # Tile 1: Grid plate with center cross
    d.rectangle([32, 0, 63, 31], outline=(30, 41, 59, 255), width=1)
    d.line([(48, 0), (48, 31)], fill=(20, 30, 48, 255), width=1)
    d.line([(32, 16), (63, 16)], fill=(20, 30, 48, 255), width=1)
    # Obstacle tile (0, 32): Slate server barrier with cyan neon trim
    d.rectangle([0, 32, 31, 63], fill=(30, 41, 59, 255), outline=(51, 65, 85, 255), width=1)
    d.line([(0, 32), (31, 32)], fill=(56, 189, 248, 255), width=2)
    tiles.save("assets/environment/tileset.png")
    print("Saved assets/environment/tileset.png")

def create_entity_placeholders():
    # Player: Geometric Cyan Arrow / Ship Triangle (32x32)
    p = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    dp = ImageDraw.Draw(p)
    dp.polygon([(26, 16), (6, 6), (10, 16), (6, 26)], fill=(56, 189, 248, 255), outline=(224, 242, 254, 255))
    dp.ellipse([12, 14, 16, 18], fill=(255, 255, 255, 255))
    p.save("assets/player/player.png")

    # Chaser: Geometric Crimson Diamond (32x32)
    c = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    dc = ImageDraw.Draw(c)
    dc.polygon([(16, 3), (29, 16), (16, 29), (3, 16)], fill=(244, 63, 94, 255), outline=(251, 113, 133, 255))
    dc.polygon([(16, 8), (24, 16), (16, 24), (8, 16)], fill=(190, 18, 60, 255))
    dc.ellipse([14, 14, 18, 18], fill=(255, 255, 255, 255))
    c.save("assets/enemies/chaser.png")

    # Shooter: Geometric Amber Hexagon (32x32)
    s = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    ds = ImageDraw.Draw(s)
    ds.polygon([(27, 16), (21, 6), (9, 6), (3, 16), (9, 26), (21, 26)], fill=(245, 158, 11, 255), outline=(253, 230, 138, 255))
    ds.ellipse([12, 12, 20, 20], fill=(217, 119, 6, 255))
    ds.ellipse([14, 14, 18, 18], fill=(255, 255, 255, 255))
    s.save("assets/enemies/shooter.png")

    # Dasher: Geometric Magenta Chevron (32x32)
    da = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    dda = ImageDraw.Draw(da)
    dda.polygon([(28, 16), (6, 5), (14, 16), (6, 27)], fill=(217, 70, 239, 255), outline=(245, 208, 254, 255))
    dda.polygon([(22, 16), (10, 9), (15, 16), (10, 23)], fill=(162, 28, 175, 255))
    da.save("assets/enemies/dasher.png")

    # Boss: Geometric Ruby Octagon (64x64)
    b = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    db = ImageDraw.Draw(b)
    pts = []
    for i in range(8):
        angle = i * (math.pi / 4.0)
        pts.append((32 + int(math.cos(angle) * 26), 32 + int(math.sin(angle) * 26)))
    db.polygon(pts, fill=(136, 19, 55, 255), outline=(251, 113, 133, 255))
    db.ellipse([20, 20, 44, 44], fill=(244, 63, 94, 255), outline=(254, 205, 211, 255), width=2)
    db.ellipse([27, 27, 37, 37], fill=(255, 255, 255, 255))
    b.save("assets/enemies/boss.png")
    print("Saved all geometric placeholder entity assets!")

if __name__ == "__main__":
    ensure_dirs()
    create_ui_hearts()
    create_weapon_assets()
    create_environment_assets()
    create_entity_placeholders()
    print("=== Geometric placeholder assets created successfully ===")
