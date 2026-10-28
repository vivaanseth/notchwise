#include "AnimationClips.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include "AnimationClipData.h"
#include "CorpusClipData.h"
#include "MeasuredMotion.h"

namespace MotionClips {
namespace {
constexpr uint8_t kHold = 1, kTopologySnap = 2;
struct DataView {
  const VectorFace::PackedShape* geometry;
  const Keyframe* keys;
  const Palette* sourcePalettes;
};
// Views contain only pointers; no geometry, keys, or palette records are copied.
constexpr DataView baselineDataView() {
  return {MotionClipData::kGeometry, MotionClipData::kKeys, MotionClipData::kSourcePalettes};
}
constexpr DataView corpusDataView() {
  return {CorpusClipData::kGeometry, CorpusClipData::kKeys, CorpusClipData::kSourcePalettes};
}
constexpr DataView dataView(ClipId id) {
  return static_cast<size_t>(id) < kBaselineClipCount ? baselineDataView() : corpusDataView();
}
constexpr bool corpusRegistrationValid() {
  if (CorpusClipData::kClipCount != kClipCount - kBaselineClipCount ||
      sizeof(CorpusClipData::kDefinitions) / sizeof(Definition) != CorpusClipData::kClipCount) return false;
  for (size_t id = kBaselineClipCount; id < kClipCount; ++id) {
    size_t matches = 0;
    for (const auto& d : CorpusClipData::kDefinitions)
      if (static_cast<size_t>(d.id) == id) ++matches;
    if (matches != 1) return false;
  }
  return true;
}
static_assert(sizeof(MotionClipData::kDefinitions) / sizeof(Definition) == kBaselineClipCount,
              "Baseline clip registry changed");
static_assert(corpusRegistrationValid(), "Generated corpus must match the registered clip IDs exactly");
float bound(float value, float lo, float hi, float fallback = 0) {
  return std::isfinite(value) ? std::max(lo, std::min(hi, value)) : fallback;
}
float mix(float a, float b, float t) { return a + (b - a) * t; }
bool validId(ClipId id) { return static_cast<size_t>(id) < kClipCount; }
bool keysCompatible(const DataView& data, const Keyframe& a, const Keyframe& b) {
  if (a.shapeCount != b.shapeCount || (a.flags & kHold) || (b.flags & kTopologySnap)) return false;
  for (size_t i = 0; i < a.shapeCount; ++i) {
    const auto& x = data.geometry[a.shapeOffset + i];
    const auto& y = data.geometry[b.shapeOffset + i];
    if (x.vertexCount != y.vertexCount || x.clipShape != y.clipShape) return false;
  }
  return true;
}
Palette colors(const DataView& data, const Parameters& p, uint16_t source) {
  if (p.palette == PaletteId::Source) return data.sourcePalettes[source];
  if (p.palette == PaletteId::Custom) return p.customPalette;
  return namedPalette(p.palette);
}
void transform(VectorFace::Shape& shape, float x, float y, float width, float height) {
  const float sx = shape.width > .0001F ? width / shape.width : 1;
  const float sy = shape.height > .0001F ? height / shape.height : 1;
  for (size_t j = 0; j < shape.vertexCount; ++j) {
    shape.vertices[j].x = x + (shape.vertices[j].x - shape.centerX) * sx;
    shape.vertices[j].y = y + (shape.vertices[j].y - shape.centerY) * sy;
  }
  shape.centerX = x; shape.centerY = y; shape.width = width; shape.height = height;
}
void gazeAndMirror(VectorFace::Frame& frame, const Parameters& p) {
  for (size_t i = 0; i < frame.shapeCount; ++i) {
    auto& shape = frame.shapes[i];
    if (shape.clipShape >= 0) {
      const auto& parent = frame.shapes[shape.clipShape];
      const float dx = p.gazeX * std::min(10.0F, parent.width * .12F);
      const float dy = p.gazeY * std::min(8.0F, parent.height * .12F);
      transform(shape, shape.centerX + dx, shape.centerY + dy, shape.width, shape.height);
    }
  }
  if (p.mirror) for (size_t i = 0; i < frame.shapeCount; ++i) {
    auto& shape = frame.shapes[i];
    shape.centerX = 239.0F - shape.centerX; shape.rotation = -shape.rotation;
    for (size_t j = 0; j < shape.vertexCount; ++j) shape.vertices[j].x = 239.0F - shape.vertices[j].x;
  }
}
bool decode(const DataView& data, const Definition& d, double time, const Parameters& p, Sample& out) {
  if (!d.keyCount) return false;
  const auto* keys = data.keys + d.firstKey;
  size_t lo = 0, hi = d.keyCount;
  while (lo < hi) {
    const size_t middle = lo + (hi - lo) / 2;
    if (keys[middle].localUs <= time) lo = middle + 1; else hi = middle;
  }
  const size_t index = lo ? lo - 1 : 0;
  const auto& a = keys[index];
  const auto& b = keys[index + 1 < d.keyCount ? index + 1 : index];
  float t = 0;
  if (b.localUs > a.localUs && keysCompatible(data, a, b))
    t = static_cast<float>((time - a.localUs) / (b.localUs - a.localUs));
  t = bound(t, 0, 1);
  const Palette ca = colors(data, p, sourcePaletteIndex(a)), cb = colors(data, p, sourcePaletteIndex(b));
  out.frame.shapeCount = 0; out.frame.background565 = ca.colors[0];
  uint8_t remap[VectorFace::kMaxShapes]{};
  for (size_t i = 0; i < a.shapeCount; ++i) {
    auto from = data.geometry[a.shapeOffset + i];
    auto to = t > 0 ? data.geometry[b.shapeOffset + i] : from;
    const uint16_t role = from.color565;
    if (!p.effects && role == static_cast<uint16_t>(ColorRole::Effect)) continue;
    from.color565 = ca.colors[role];
    to.color565 = (t > 0 ? cb : ca).colors[to.color565];
    const uint8_t target = out.frame.shapeCount;
    if (!VectorFace::interpolate(from, to, t, out.frame.shapes[target])) return false;
    auto& shape = out.frame.shapes[target];
    out.frame.colorRoles[target] = static_cast<uint8_t>(role);
    if (shape.clipShape >= 0) shape.clipShape = static_cast<int8_t>(remap[shape.clipShape]);
    remap[i] = target; ++out.frame.shapeCount;
    // Intensity attenuates measured transform deltas around the clip's own
    // entry geometry. Contour topology and its authored timing remain intact.
    if (p.intensity < 1 && i < keys[0].shapeCount) {
      const auto& base = data.geometry[keys[0].shapeOffset + i];
      if (base.color565 == role && base.clipShape == from.clipShape) {
        transform(shape, mix(base.centerX64 / 64.0F, shape.centerX, p.intensity),
            mix(base.centerY64 / 64.0F, shape.centerY, p.intensity),
            mix(base.width64 / 64.0F, shape.width, p.intensity),
            mix(base.height64 / 64.0F, shape.height, p.intensity));
      }
    }
  }
  out.keyframe = static_cast<uint16_t>(index);
  return true;
}
}  // namespace

const Definition& definition(ClipId id) {
  if (static_cast<size_t>(id) < kBaselineClipCount)
    return MotionClipData::kDefinitions[static_cast<size_t>(id)];
  // Compilation order is not a production ID; every corpus array has its
  // own offsets and the generated definition explicitly supplies its ID.
  for (const auto& d : CorpusClipData::kDefinitions) if (d.id == id) return d;
  return MotionClipData::kDefinitions[0];
}
const char* faceName(FaceKind face) {
  static constexpr const char* names[] = {"Compatible held face", "Oval", "Covered", "Flower", "Converged dots", "Heart accents", "Open oval", "Attentive", "Angry glare"};
  return static_cast<size_t>(face) < sizeof(names) / sizeof(names[0]) ? names[static_cast<size_t>(face)] : "Unknown";
}
const char* paletteName(PaletteId id) {
  static constexpr const char* names[] = {"SOURCE", "BLUE", "MINT", "PURPLE", "WARM", "CUSTOM"};
  return static_cast<size_t>(id) < 6 ? names[static_cast<size_t>(id)] : "SOURCE";
}
Palette namedPalette(PaletteId id) {
  const size_t index = static_cast<size_t>(id);
  return MotionClipData::kNamedPalettes[index < 5 ? index : 0];
}
Parameters referenceParameters() { return {}; }
Parameters boundedParameters(ClipId id, const Parameters& input) {
  Parameters p = input;
  const auto& d = definition(id);
  p.intensity = d.parameters & Intensity ? bound(p.intensity, 0, 1, 1) : 1;
  p.gazeX = d.parameters & Gaze ? bound(p.gazeX, -1, 1) : 0;
  p.gazeY = d.parameters & Gaze ? bound(p.gazeY, -1, 1) : 0;
  p.mirror = p.mirror && (d.parameters & Mirror);
  p.effects = p.effects || !(d.parameters & Effects);
  if (p.palette >= PaletteId::Count || !(d.parameters & Appearance)) p.palette = PaletteId::Source;
  if (!(d.parameters & Duration)) p.durationUs = 0;
  else if (p.durationUs) p.durationUs = std::max(d.minimumDurationUs, std::min(d.maximumDurationUs, p.durationUs));
  p.holdUs = d.parameters & Hold ? std::min(p.holdUs, d.maximumHoldUs) : 0;
  return p;
}
uint32_t playbackDurationUs(ClipId id, const Parameters& input) {
  const auto p = boundedParameters(id, input);
  return (p.durationUs ? p.durationUs : definition(id).durationUs) + p.holdUs;
}
bool compatible(const VectorFace::Frame& a, const VectorFace::Frame& b) {
  if (!a.shapeCount || a.shapeCount > VectorFace::kMaxShapes || a.shapeCount != b.shapeCount) return false;
  for (size_t i = 0; i < a.shapeCount; ++i)
    if (a.shapes[i].vertexCount != b.shapes[i].vertexCount || a.shapes[i].clipShape != b.shapes[i].clipShape) return false;
  return true;
}
void enforceRoundSafety(VectorFace::Frame& frame, float margin) {
  float furthest = 0;
  for (size_t i = 0; i < frame.shapeCount; ++i)
    for (size_t j = 0; j < frame.shapes[i].vertexCount; ++j)
      furthest = std::max(furthest, std::hypot(frame.shapes[i].vertices[j].x - 119.5F,
                                            frame.shapes[i].vertices[j].y - 119.5F));
  const float radius = 119.5F - bound(margin, 0, 10, 1);
  if (furthest <= radius || furthest == 0) return;
  const float scale = radius / furthest;
  for (size_t i = 0; i < frame.shapeCount; ++i) {
    auto& s = frame.shapes[i];
    s.centerX = 119.5F + (s.centerX - 119.5F) * scale;
    s.centerY = 119.5F + (s.centerY - 119.5F) * scale;
    s.width *= scale; s.height *= scale;
    for (size_t j = 0; j < s.vertexCount; ++j) {
      s.vertices[j].x = 119.5F + (s.vertices[j].x - 119.5F) * scale;
      s.vertices[j].y = 119.5F + (s.vertices[j].y - 119.5F) * scale;
    }
  }
}
bool sample(ClipId id, double localUs, const Parameters& input, Sample& out) {
  if (!validId(id) || !std::isfinite(localUs) || localUs < 0) return false;
  const Parameters p = boundedParameters(id, input);
  const auto& d = definition(id);
  if (id == ClipId::RetreatGesture) {
    VectorFace::Frame held{}; held.shapeCount = 4;
    const auto palette = colors(baselineDataView(), p, MotionClipData::kRetreatBasePalette);
    held.background565 = palette.colors[0];
    for (size_t i = 0; i < held.shapeCount; ++i) {
      auto shape = MotionClipData::kGeometry[MotionClipData::kRetreatBaseShape + i];
      held.colorRoles[i] = static_cast<uint8_t>(shape.color565);
      shape.color565 = palette.colors[shape.color565];
      if (!VectorFace::unpack(shape, held.shapes[i])) return false;
    }
    return applyRetreat(held, localUs, p, out);
  }
  const uint32_t duration = p.durationUs ? p.durationUs : d.durationUs;
  const double age = std::min(localUs, static_cast<double>(duration));
  double referenceUs = age * d.durationUs / duration;
  const double nearest = std::round(referenceUs);
  if (std::fabs(referenceUs - nearest) < 1e-6) referenceUs = nearest;
  const auto& geometry = id == ClipId::SoftExit ? definition(ClipId::OvalHold) : d;
  if (!decode(dataView(id), geometry, id == ClipId::SoftExit ? 0 : referenceUs, p, out)) return false;
  gazeAndMirror(out.frame, p);
  // Exact reference defaults never touch accepted geometry. Safe product
  // deformations and gaze targets are projected into the visible circle.
  if (p.intensity != 1 || p.gazeX || p.gazeY) enforceRoundSafety(out.frame);
  out.localTimeUs = static_cast<uint32_t>(std::min(localUs, static_cast<double>(playbackDurationUs(id, p))));
  out.face = localUs >= duration ? d.endsIn : d.startsIn;
  out.finished = localUs >= playbackDurationUs(id, p);
  out.bounds = VectorFace::measureBounds(out.frame);
  return !out.bounds.invalidShapes;
}

bool applyRetreat(const VectorFace::Frame& held, double localUs, const Parameters& input, Sample& out) {
  if (!std::isfinite(localUs) || localUs < 0 || held.shapeCount < 2 ||
      held.shapeCount > VectorFace::kMaxShapes || VectorFace::measureBounds(held).invalidShapes ||
      held.shapes[0].clipShape != -1 || held.shapes[1].clipShape != -1) return false;
  for (size_t i = 2; i < held.shapeCount; ++i)
    if (held.shapes[i].clipShape < 0 || held.shapes[i].clipShape > 1) return false;
  const Parameters p = boundedParameters(ClipId::RetreatGesture, input);
  const auto& d = definition(ClipId::RetreatGesture);
  const uint32_t duration = p.durationUs ? p.durationUs : d.durationUs;
  const uint32_t sampledUs = static_cast<uint32_t>(std::llround(std::min(localUs, static_cast<double>(duration)) * d.durationUs / duration));
  MeasuredMotion::Sample base{}, at{};
  const auto track = MeasuredMotion::curiousAttention();
  if (!MeasuredMotion::sample(track, 0, base) || !MeasuredMotion::sample(track, sampledUs, at)) return false;
  const auto delta = [&](MeasuredMotion::Channel c) { return (at.channels[c] - base.channels[c]) * p.intensity; };
  using namespace MeasuredMotion;
  out.frame = held;
  if (p.palette != PaletteId::Source) {
    const auto palette = p.palette == PaletteId::Custom ? p.customPalette : namedPalette(p.palette);
    out.frame.background565 = palette.colors[0];
    for (size_t i = 0; i < out.frame.shapeCount; ++i) {
      const uint8_t role = out.frame.colorRoles[i];
      if (role > 0 && role < static_cast<uint8_t>(ColorRole::Count))
        out.frame.shapes[i].color565 = palette.colors[role];
    }
  }
  const float mirrorSign = p.mirror ? -1.0F : 1.0F;
  const float dx = delta(GlobalX) * mirrorSign, dy = delta(GlobalY);
  const float spacing = delta(MeasuredMotion::Spacing), mismatch = delta(VerticalMismatch) * mirrorSign;
  for (size_t i = 0; i < held.shapeCount; ++i) {
    const size_t side = i < 2 ? i : static_cast<size_t>(held.shapes[i].clipShape);
    const auto& anchor = held.shapes[side];
    const float direction = side ? 1.0F : -1.0F;
    const bool measuredRight = p.mirror ? !side : side;
    const Channel width = measuredRight ? RightWidth : LeftWidth, height = measuredRight ? RightHeight : LeftHeight;
    const float sx = 1 + delta(width) / std::max(1.0F, base.channels[width]);
    const float sy = 1 + delta(height) / std::max(1.0F, base.channels[height]);
    const float x = anchor.centerX + dx + direction * spacing * .5F;
    const float y = anchor.centerY + dy + direction * mismatch * .5F;
    auto& target = out.frame.shapes[i];
    const auto& original = held.shapes[i];
    const float pupilX = i < 2 ? 0 : delta(measuredRight ? RightPupilX : LeftPupilX) * mirrorSign;
    const float pupilY = i < 2 ? 0 : delta(measuredRight ? RightPupilY : LeftPupilY);
    for (size_t j = 0; j < target.vertexCount; ++j) {
      target.vertices[j].x = x + (original.vertices[j].x - anchor.centerX) * sx + pupilX;
      target.vertices[j].y = y + (original.vertices[j].y - anchor.centerY) * sy + pupilY;
    }
    target.centerX = x + (original.centerX - anchor.centerX) * sx + pupilX;
    target.centerY = y + (original.centerY - anchor.centerY) * sy + pupilY;
    target.width *= sx; target.height *= sy;
  }
  Parameters gazeParameters = p;
  gazeParameters.mirror = false; // Mirror gesture deltas, never flip the held face at entry.
  gazeAndMirror(out.frame, gazeParameters);
  enforceRoundSafety(out.frame);
  out.localTimeUs = static_cast<uint32_t>(std::min(localUs, static_cast<double>(playbackDurationUs(ClipId::RetreatGesture, p))));
  out.keyframe = 0;
  for (size_t i = 0; i < track.count; ++i) if (track.knots[i].timestampUs <= sampledUs) out.keyframe = static_cast<uint16_t>(i);
  out.face = FaceKind::Attentive;
  out.finished = localUs >= playbackDurationUs(ClipId::RetreatGesture, p);
  out.bounds = VectorFace::measureBounds(out.frame);
  return !out.bounds.invalidShapes;
}
size_t metadataBytes() {
  size_t bytes = sizeof(MotionClipData::kDefinitions);
  for (const auto& d : MotionClipData::kDefinitions) bytes += std::strlen(d.name) + 1;
  return bytes + CorpusClipData::kMetadataBytes;
}
size_t keyframeBytes() { return sizeof(MotionClipData::kKeys) + MeasuredMotion::curiousAttentionBytes() + CorpusClipData::kKeyframeBytes; }
size_t geometryBytes() { return sizeof(MotionClipData::kGeometry) + CorpusClipData::kGeometryBytes; }
size_t paletteBytes() { return sizeof(MotionClipData::kSourcePalettes) + sizeof(MotionClipData::kNamedPalettes) + CorpusClipData::kPaletteBytes; }
}  // namespace MotionClips
