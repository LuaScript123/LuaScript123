-- Cosmetics only: combat stats are defined once in Config.Combat.
local Catalog = {}
Catalog.DefaultSword = "Iron"
Catalog.DefaultFaction = "Redcliff"
Catalog.SwordOrder = { "Iron", "Redcliff", "Korblox", "Greywolf", "Overseer" }
Catalog.Swords = {
    Iron = { Name = "Epee de fer", Price = 0, Blade = { 201, 217, 229 }, Guard = { 209, 171, 89 }, Accent = { 92, 67, 44 }, Style = "Classic" },
    Redcliff = { Name = "Lame Redcliff", Price = 100, Blade = { 224, 212, 199 }, Guard = { 195, 55, 51 }, Accent = { 238, 185, 90 }, Style = "Cross" },
    Korblox = { Name = "Croc Korblox", Price = 150, Blade = { 126, 206, 234 }, Guard = { 43, 49, 69 }, Accent = { 76, 154, 224 }, Style = "Fang" },
    Greywolf = { Name = "Acier Greywolf", Price = 200, Blade = { 201, 205, 214 }, Guard = { 93, 100, 116 }, Accent = { 234, 231, 216 }, Style = "Wolf" },
    Overseer = { Name = "Oeil Overseer", Price = 250, Blade = { 145, 214, 119 }, Guard = { 48, 81, 56 }, Accent = { 172, 241, 88 }, Style = "Eye" },
}
Catalog.FactionOrder = { "Redcliff", "Korblox", "Greywolf", "Overseer" }
Catalog.Factions = {
    Redcliff = { Name = "Redcliff", Color = { 184, 53, 47 }, Trim = { 221, 180, 92 }, Description = "Acier, ecarlate et or." },
    Korblox = { Name = "Korblox", Color = { 54, 105, 151 }, Trim = { 121, 212, 238 }, Description = "Armure sombre et bleu glacial." },
    Greywolf = { Name = "Greywolf", Color = { 107, 114, 126 }, Trim = { 218, 220, 225 }, Description = "Gris ardoise et argent." },
    Overseer = { Name = "Overseer", Color = { 54, 109, 65 }, Trim = { 151, 221, 83 }, Description = "Emeraude et vert lumineux." },
}
return Catalog
