class StudioPalette {
  final String id, name;
  final int primary;
  final List<int> colors;
  const StudioPalette(this.id, this.name, this.primary, this.colors);
}

const studioPalettes = [
  StudioPalette('aurora', '琉光极境', 0xff2e68cd, [
    0xff4c8dff,
    0xffff7eb6,
    0xff8a6bff,
    0xff75d9ef,
  ]),
  StudioPalette('dawn', '日落鎏金', 0xffaa572c, [
    0xffffba76,
    0xffff7e91,
    0xffcb8bd8,
    0xffffdba0,
  ]),
  StudioPalette('lagoon', '青屿潮汐', 0xff147b80, [
    0xff63cfc3,
    0xff79c6e8,
    0xffbed8a0,
    0xff76b8e7,
  ]),
  StudioPalette('violet', '鸢尾星云', 0xff7950c8, [
    0xffa885f2,
    0xffdb9dd4,
    0xff8da9f2,
    0xffc7a4e9,
  ]),
  StudioPalette('rose', '蔷薇暮色', 0xffb34874, [
    0xfff49dc0,
    0xffecb899,
    0xffc6a3e1,
    0xfff4d1bb,
  ]),
  StudioPalette('forest', '雾野森境', 0xff367c52, [
    0xff8acb9e,
    0xffc2ce8a,
    0xff86bdb4,
    0xffb2d9ab,
  ]),
  StudioPalette('glacier', '冰川月白', 0xff426b9e, [
    0xff9bbfe4,
    0xffc0c9e8,
    0xff89cbd3,
    0xffc8ddf0,
  ]),
  StudioPalette('ember', '赤陶余晖', 0xffa25648, [
    0xffe9a58e,
    0xffd6b4a4,
    0xffd19fa8,
    0xffe2c397,
  ]),
];

StudioPalette paletteById(String id) => studioPalettes.firstWhere(
  (p) => p.id == id,
  orElse: () => studioPalettes.first,
);
