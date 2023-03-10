using Starlight

const window_width = 600
const window_height = 400
const img_path = joinpath("assets/png/player.png")

a = App(; wdth=window_width, hght=window_height, bgrd=colorant"black")

Starlight.awake!(a)

Sprite(img_path; scale=XYZ(0.5,0.5,0.5), pos=XYZ(300, 300))

