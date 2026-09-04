# Fuse Dragons 2

## Note
All scripts should be checked in here--no scripts should be attached to parts in Roblox Studio

## luau-lsp
This can be built from source, but you can also download the binary from the Releases in github.
If so, on macos you need to do `xattr -cr ./luau-lsp` to allow it to run.
If editing with emacs, you eglot configuration for it in .emacs needs to point to it (probably in ~/bin)

## Tips
-- when there is a new version of rojo, edit the foreman.toml then
```bash
foreman install
# exit emacs / any rojo running otherwise you'll get a zsh killed rojo error
# then
rojo plugin install

## Textures
To make a color map for a rarity of a dragon, run this
```bash
magick Dragon_Green_Uncommon.png Dragon_Texture_Green_Alpha.png \( -clone 0 -clone 1 -compose lighten -composite \) -swap 0,2 +delete -alpha off -compose copy_opacity -composite green_uncommon_colormap.png
```
use the black & white "alpha" texture for emissive map

## plugin
To build and run the plugin
```bash
cd ~/md/plugin
make
```
