#include "FaceMotionEngine.h"
#include "MeasuredMotion.h"

#include <algorithm>
#include <cmath>

namespace FaceMotion {
namespace {
constexpr float D = 480.0F;
constexpr float kCenter = D * 0.5F;
constexpr float kPi = 3.14159265358979323846F;

// O-H/O-M entries name observed forms; I-H/I-M entries and every millisecond
// below are tunable reconstruction hypotheses, not source-frame measurements.
#define P(id, family, motif, eyes, fx, w, h, s, y, a, tilt, pup, lt, lb, label, evidence) \
  {PoseId::id, Family::family, Motif::motif, eyes, fx, w, h, s, y, a, tilt, pup, lt, lb, label, evidence}
constexpr PoseDefinition kCatalog[kPoseCount] = {
  P(F01, Round, Dot, 2, 0, .30F,.42F,.32F, .00F,.00F,.0F,.39F,.00F,.00F,"Neutral open","O-H"),
  P(F02, Round, Dot, 2, 0, .30F,.41F,.32F,-.015F,.015F,.5F,.38F,.00F,.00F,"Soft attentive","O-H"),
  P(F03, Round, Dot, 2, 0, .30F,.42F,.32F,-.01F,.065F,2.4F,.39F,.015F,.00F,"Curious asymmetric","O-H"),
  P(F04, Capsule, Dot,2,0,.31F,.31F,.31F,.01F,.015F,1.8F,.37F,.08F,.00F,"Focused narrow","O-H"),
  P(F05, Capsule, Dot,2,0,.32F,.22F,.31F,.035F,.02F,1.2F,.35F,.20F,.00F,"Sleepy half-lid","O-H"),
  P(F06, Slit, None,2,0,.30F,.045F,.31F,.07F,.00F,.0F,.00F,.00F,.00F,"Sleep slit","O-H"),
  P(F07, Arc, None,2,0,.25F,.085F,.31F,-.02F,.00F,.0F,.00F,.00F,.00F,"Happy closed","O-H"),
  P(F08, Round, Dot,2,0,.31F,.49F,.345F,-.01F,.00F,.0F,.26F,.00F,.00F,"Wide alert","O-H"),
  P(F09, Capsule, Dot,2,0,.32F,.29F,.31F,.00F,.05F,3.0F,.35F,.14F,.00F,"Annoyed determined","O-M"),
  P(F10, Capsule, Dot,2,0,.29F,.28F,.31F,.02F,.08F,4.0F,.28F,.18F,.00F,"Anxious wince","I-M"),
  P(F11, Round, Dot,2,0,.27F,.35F,.31F,.045F,.025F,1.5F,.32F,.13F,.00F,"Sad downcast","I-M"),
  P(F12, Round, Dot,2,0,.30F,.36F,.32F,.01F,.035F,1.7F,.37F,.07F,.00F,"Thinking drift","I-H"),
  P(F13, Round, Dot,2,0,.30F,.39F,.32F,-.01F,.00F,.0F,.37F,.03F,.00F,"Listening","I-M"),
  P(F14, Capsule, Dot,2,0,.30F,.30F,.315F,.005F,.00F,.6F,.35F,.09F,.00F,"Working effort","I-M"),
  P(R01, Round, Spiral,2,0,.30F,.43F,.32F,.00F,.015F,3.0F,.42F,.00F,.00F,"Dizzy spiral","O-H"),
  P(R02, Round, Bolt,2,0,.32F,.52F,.35F,-.01F,.00F,.0F,.43F,.00F,.00F,"Charged lightning","O-H"),
  P(R03, Round, Heart,2,0,.32F,.47F,.33F,-.01F,.00F,.0F,.42F,.00F,.00F,"Heart eyes","O-H"),
  P(R04, Petal, Flower,2,0,.30F,.43F,.33F,.00F,.02F,2.0F,.42F,.00F,.00F,"Flower petal","O-H"),
  P(R05, Capsule,None,2,WarmAccent,.28F,.49F,.32F,.00F,.00F,.0F,.00F,.00F,.00F,"Hot ovals","O-H"),
  P(R06, Arc, None,2,Hearts,.25F,.085F,.31F,-.02F,.00F,.0F,.00F,.00F,.00F,"Heart burst","O-H"),
  P(R07, Arc, None,2,Sparkle,.25F,.085F,.31F,-.02F,.00F,.0F,.00F,.00F,.00F,"Sparkle close","O-H"),
  P(R08, Round, Dot,2,0,.30F,.46F,.33F,-.01F,.00F,.0F,.12F,.00F,.00F,"Freeze tiny pupils","I-M"),
  P(R09, Capsule,Dot,2,WarmAccent,.33F,.30F,.32F,.02F,.12F,5.0F,.27F,.14F,.00F,"Error recoil","I-M"),
  P(R10, Round, Dot,2,0,.30F,.42F,.32F,-.015F,.00F,.0F,.38F,.00F,.00F,"Wake overshoot","I-H"),
  P(T01, Round, Dot,2,0,.30F,.42F,.32F,.00F,.00F,.0F,.39F,.00F,.00F,"Attention lead","I-H"),
  P(T02, Round, Dot,2,0,.31F,.34F,.32F,.00F,.00F,.0F,.39F,.08F,.00F,"Micro pinch","I-H"),
  P(T03, Slit, None,2,0,.30F,.05F,.31F,.025F,.00F,.0F,.00F,.00F,.00F,"Squeeze gate","O-H"),
  P(T04, Slit, None,2,0,.30F,.025F,.31F,.025F,.00F,.0F,.00F,.00F,.00F,"Full-close cover","O-H"),
  P(T05, Capsule,Dot,2,0,.29F,.17F,.31F,.00F,.10F,3.0F,.30F,.25F,.00F,"Asymmetric close","I-H"),
  P(T06, Capsule,Dot,2,0,.34F,.27F,.31F,.01F,.09F,4.0F,.32F,.06F,.00F,"Impact squash","I-M"),
  P(T07, Round, Dot,2,0,.34F,.49F,.34F,.00F,.00F,.0F,.37F,.00F,.00F,"Reopen overshoot","O-H"),
  P(T08, Round, Dot,2,0,.30F,.42F,.35F,.00F,.00F,.0F,.39F,.00F,.00F,"Spacing overshoot","I-M"),
  P(T09, Round, Dot,2,0,.30F,.42F,.32F,.00F,.00F,.0F,.39F,.00F,.00F,"Pupil catch-up","I-H"),
  P(T10, Multi, Dot,4,0,.16F,.25F,.62F,.00F,.03F,1.0F,.34F,.00F,.00F,"Multiplicity bridge","O-H"),
  P(T11, Collage,None,2,Flash,.30F,.42F,.32F,.00F,.00F,.0F,.00F,.00F,.00F,"Flash reset","O-H"),
  P(T12, Collage,Dot,2,Collision,.30F,.42F,.32F,.00F,.08F,4.0F,.36F,.00F,.00F,"Collision collage","O-H"),
  P(C01, Slit, None,2,0,.30F,.025F,.32F,.00F,.00F,.0F,.00F,.00F,.00F,"Neutral blink","I-M"),
  P(C02, Arc, None,2,0,.25F,.085F,.31F,-.02F,.00F,.0F,.00F,.00F,.00F,"Happy semantic close","O-H"),
  P(C03, Slit, None,2,0,.30F,.045F,.31F,.06F,.00F,.0F,.00F,.00F,.00F,"Sleepy closure","O-H"),
  P(C04, Slit, None,2,0,.30F,.035F,.31F,.01F,.10F,4.0F,.00F,.00F,.00F,"Asymmetric wince","I-H"),
  P(S01, Multi,Dot,4,0,.16F,.25F,.62F,.00F,.015F,1.0F,.34F,.00F,.00F,"Four-eye contact","O-H"),
  P(S02, Multi,Oval,4,0,.15F,.24F,.60F,.00F,.08F,2.0F,.35F,.00F,.00F,"Split mixed pair","O-H"),
  P(S03, Collage,Dot,2,Collision,.30F,.42F,.32F,.00F,.08F,3.0F,.37F,.00F,.00F,"Collision collage","O-H"),
  P(S04, Petal,Flower,4,0,.15F,.23F,.58F,.00F,.05F,3.0F,.36F,.00F,.00F,"Rare lobed contact","O-M")
};
#undef P

struct Timing {
  uint16_t attention = 110, gateClose = 170, gateHold = 66;
  uint16_t peak = 140, overshoot = 100, settle = 360;
  uint16_t blinkClose = 105, blinkHold = 42, blinkOpen = 145;
  uint16_t sleepClose = 290, wakeSettle = 430, social = 680;
};
constexpr Timing kTiming{};

float clamp(float v, float lo, float hi) { return std::max(lo, std::min(hi, v)); }
float smooth(float t) { t = clamp(t, 0.0F, 1.0F); return t*t*(3.0F-2.0F*t); }
float mix(float a, float b, float t) { return a + (b-a)*t; }
bool reached(uint32_t now, uint32_t at) { return static_cast<int32_t>(now-at) >= 0; }
float elapsed(uint32_t now, uint32_t start, float duration) {
  return clamp(static_cast<float>(now-start)/duration, 0.0F, 1.0F);
}
bool valid(PoseId pose) { return static_cast<uint8_t>(pose)<kPoseCount; }

Frame authored(PoseId id, float intensity, uint8_t look) {
  const PoseDefinition& p = poseDefinition(id);
  Frame f{};
  f.pose = p.id; f.family=p.family; f.motif=p.motif;
  f.eyeCount=p.eyeCount; f.lookId=look; f.effects=p.effects;
  f.intensity=clamp(intensity,0.0F,1.0F);
  float h = p.height * D;
  float w = p.width * D;
  float spacing = p.spacing * D;
  if (id==PoseId::F08 || id==PoseId::R02) {
    h *= 1.0F + .12F*f.intensity;
    spacing *= 1.0F + .045F*f.intensity;
  }
  if (id==PoseId::R09) { h *= 1.0F-.12F*f.intensity; w *= 1.0F+.10F*f.intensity; }
  for (uint8_t i=0;i<f.eyeCount;i++) {
    Eye& e=f.eyes[i];
    const float side=(i%2==0?-1.0F:1.0F);
    const float slot=f.eyeCount==4 ? (static_cast<float>(i)-1.5F)/3.0F : side*.5F;
    const float asym=(i%2==0?-1.0F:1.0F)*p.asymmetry*f.intensity;
    e.x=kCenter+slot*spacing;
    e.y=kCenter+p.y*D+(f.eyeCount==4 && i%2 ? 3.0F:-3.0F);
    e.width=w*(1.0F+asym);
    e.height=h*(1.0F-asym*.35F);
    e.rotation=side*p.tilt*f.intensity;
    e.pupilWidth=e.width*p.pupilScale;
    e.pupilHeight=std::min(e.height*.46F,e.pupilWidth);
    e.pupilX=side*(-.04F*e.width); // neutral 4% inward convergence
    e.pupilY=0;
    e.lidTop=p.lidTop;
    e.lidBottom=p.lidBottom;
    if (p.motif==Motif::None || p.family==Family::Arc || p.family==Family::Slit) {
      e.pupilWidth=e.pupilHeight=0;
    }
  }
  return f;
}

void blendGeometry(Frame& out,const Frame& a,const Frame& b,float t) {
  t=smooth(t);
  out=a;
  out.pose=b.pose;
  out.effects=b.effects;
  out.intensity=mix(a.intensity,b.intensity,t);
  for (uint8_t i=0;i<a.eyeCount && i<b.eyeCount;i++) {
    Eye& o=out.eyes[i]; const Eye& q=b.eyes[i];
    o.x=mix(o.x,q.x,t); o.y=mix(o.y,q.y,t);
    o.width=mix(o.width,q.width,t); o.height=mix(o.height,q.height,t);
    o.rotation=mix(o.rotation,q.rotation,t);
    o.pupilX=mix(o.pupilX,q.pupilX,t);o.pupilY=mix(o.pupilY,q.pupilY,t);
    o.pupilWidth=mix(o.pupilWidth,q.pupilWidth,t);
    o.pupilHeight=mix(o.pupilHeight,q.pupilHeight,t);
    o.lidTop=mix(o.lidTop,q.lidTop,t);o.lidBottom=mix(o.lidBottom,q.lidBottom,t);
  }
}

void scaleAroundPair(Frame& f,float scale,float spacingScale) {
  for (uint8_t i=0;i<f.eyeCount;i++) {
    Eye& e=f.eyes[i];
    e.x=kCenter+(e.x-kCenter)*spacingScale;
    e.width*=scale; e.height*=scale;
    e.pupilWidth*=scale; e.pupilHeight*=scale;
  }
}

void clampPupil(Eye& e) {
  if (e.pupilWidth<=0 || e.pupilHeight<=0) {e.pupilX=e.pupilY=0;return;}
  const float rx=std::max(0.0F,e.width*.5F-e.pupilWidth*.5F-e.width*.05F);
  const float ry=std::max(0.0F,e.height*.5F-e.pupilHeight*.5F-e.height*.07F
                            -(e.lidTop+e.lidBottom)*e.height*.20F);
  if (rx==0 || ry==0) {e.pupilX=e.pupilY=0;return;}
  const float v=e.pupilX*e.pupilX/(rx*rx)+e.pupilY*e.pupilY/(ry*ry);
  if (v>1) {const float s=1.0F/std::sqrt(v);e.pupilX*=s;e.pupilY*=s;}
}

void applyMeasuredAttention(Frame& frame, uint32_t elapsedMs, float intensity) {
  using namespace MeasuredMotion;
  const Track track = curiousAttention();
  Sample motion{};
  const uint32_t us = elapsedMs >= (kAttentionDurationUs + 999) / 1000 ?
      kAttentionDurationUs : elapsedMs * 1000;
  if (!sample(track, us, motion)) return;
  const auto baseline = [&](Channel c) { return track.knots[0].quarterPixels[c] * .25F; };
  const auto delta = [&](Channel c) { return motion.channels[c] - baseline(c); };
  const float gain = kProductAmplitude * intensity;
  for (uint8_t i = 0; i < frame.eyeCount && i < 2; ++i) {
    Eye& eye = frame.eyes[i];
    const float side = i == 0 ? -1.0F : 1.0F;
    const Channel width = i == 0 ? LeftWidth : RightWidth;
    const Channel height = i == 0 ? LeftHeight : RightHeight;
    const float sx = 1 + gain * delta(width) / baseline(width);
    const float sy = 1 + gain * delta(height) / baseline(height);
    // Physical source pixels become 480-space logical pixels at 2x.
    eye.x += 2 * gain * (delta(GlobalX) + side * .5F * delta(Spacing));
    eye.y += 2 * gain * (delta(GlobalY) + side * .5F * delta(VerticalMismatch));
    eye.width *= sx; eye.height *= sy;
    eye.pupilWidth *= sx; eye.pupilHeight *= sy;
    eye.pupilX = eye.pupilX * sx + 2 * gain * delta(i == 0 ? LeftPupilX : RightPupilX);
    eye.pupilY = eye.pupilY * sy + 2 * gain * delta(i == 0 ? LeftPupilY : RightPupilY);
  }
}

bool compatible(const Frame& a,const Frame& b) {
  return a.family==b.family && a.motif==b.motif &&
         a.eyeCount==b.eyeCount && a.lookId==b.lookId;
}
float overshootFor(PoseId pose,float intensity) {
  if (pose==PoseId::F08 || pose==PoseId::R02 || pose==PoseId::R10)
    return .10F+.08F*intensity;
  if (pose==PoseId::F06 || pose==PoseId::F07 || pose==PoseId::C02 ||
      pose==PoseId::R06 || pose==PoseId::R07)return .03F;
  if (pose==PoseId::F12 || pose==PoseId::F13 || pose==PoseId::F14)
    return .015F+.015F*intensity;
  if (pose==PoseId::F03 || pose==PoseId::F11)
    return .025F+.025F*intensity;
  if (pose==PoseId::R09)return .07F+.06F*intensity;
  return .04F+.05F*intensity;
}
float spacingOvershootFor(PoseId pose,float intensity) {
  return pose==PoseId::F08 || pose==PoseId::R02 || pose==PoseId::R10 ?
      .04F+.06F*intensity : overshootFor(pose,intensity)*.24F;
}
uint32_t reactionHold(PoseId pose) {
  return isSocial(pose)?2100:isTransition(pose)?900:
    pose==PoseId::R01?2400:pose==PoseId::R03?2100:
    pose==PoseId::R06?1700:1500;
}

} // namespace

const PoseDefinition& poseDefinition(PoseId id) {
  return kCatalog[valid(id)?static_cast<uint8_t>(id):0];
}
const char* poseName(PoseId id) {return poseDefinition(id).name;}
bool isPersistent(PoseId id) {return valid(id)&&static_cast<uint8_t>(id)<14;}
bool isReaction(PoseId id) {const auto v=static_cast<uint8_t>(id);return v>=14&&v<24;}
bool isTransition(PoseId id) {const auto v=static_cast<uint8_t>(id);return v>=24&&v<36;}
bool isClosure(PoseId id) {const auto v=static_cast<uint8_t>(id);return v>=36&&v<40;}
bool isSocial(PoseId id) {const auto v=static_cast<uint8_t>(id);return v>=40&&v<44;}
size_t Engine::catalogBytes() {return sizeof(kCatalog);}

uint32_t Engine::random() {
  // xorshift32: fixed state, reproducible and no allocation.
  rng_^=rng_<<13; rng_^=rng_>>17; rng_^=rng_<<5; return rng_;
}
uint32_t Engine::randomRange(uint32_t lo,uint32_t hi) {
  return lo+random()%(hi-lo+1);
}
void Engine::scheduleBlink(uint32_t now) {
  // Truncated irregular I-M distribution: median near four seconds, 1.6–8 s.
  uint32_t ms=1600+randomRange(0,2600)+randomRange(0,1800);
  if ((random()&7)==0) ms+=randomRange(800,2000);
  diag_.nextBlinkMs=now+std::min<uint32_t>(ms,8000u);
}
void Engine::scheduleIdle(uint32_t now) {
  diag_.nextIdleMs=now+randomRange(1400,4500);
}
void Engine::begin(uint32_t nowMs,uint32_t seed) {
  *this=Engine{};
  rng_=seed?seed:0x6d2b79f5u;
  lastMs_=stageStartMs_=nowMs;
  frame_=authored(PoseId::F01,.5F,0);
  sourceFrame_=frame_;
  diag_.target=PoseId::F01;
  diag_.source=PoseId::F01;
  diag_.stage=Stage::Rest;
  diag_.idleEnabled=true;
  scheduleBlink(nowMs);
  scheduleIdle(nowMs);
}
void Engine::startStage(Stage stage,uint32_t now) {
  if (stage==Stage::Rest && targetPose_==PoseId::F06 && sleeping_)
    stage=Stage::Sleep;
  diag_.stage=stage;diag_.stageProgress=0;stageStartMs_=now;
  diag_.keyframe=stage==Stage::Anticipation?1:stage==Stage::Gate?2:
    stage==Stage::Peak?3:stage==Stage::Overshoot?4:
    stage==Stage::Settle?5:stage==Stage::Social?6:0;
  diag_.settleProgress=0;
  diag_.transitionActive=(stage!=Stage::Rest && stage!=Stage::Blink && stage!=Stage::Sleep);
  if (stage==Stage::Peak && targetPose_==PoseId::F03) {
    // After a covered topology change, reopen from the covered destination.
    // For a compatible request, resolveRequest already captured the display.
    if (!measuredAttention_ && gateRequired_) sourceFrame_=frame_;
    measuredStartMs_=now;
    measuredAttention_=true;
  }
  if (stage==Stage::Rest || stage==Stage::Sleep) {
    frame_=authored(targetPose_,clipIntensity_,targetLook_);
    frame_.effectPhase=0;
    lookId_=targetLook_;
    sourcePose_=targetPose_;
    suppressBlinkUntilMs_=now+(targetPose_==PoseId::R10?500:300);
    scheduleIdle(now);
  }
}

void Engine::resolveRequest(PoseId pose,float intensity,uint32_t now) {
  if (!valid(pose))return;
  if (diag_.stage==Stage::Gate && !swapped_ && pose==PoseId::R10) {
    // Wake takes over the pending covered handoff; no exposed slit-to-open cut.
    targetPose_=pose;
    clipIntensity_=clamp(std::isfinite(intensity)?intensity:.5F,0.0F,1.0F);
    diag_.target=pose;
    return;
  }
  if (diag_.stage==Stage::Gate || (diag_.stage==Stage::Social &&
      (frame_.effects&(Flash|Collision)))) {
    pendingPose_=pose;
    pendingIntensity_=intensity;
    return; // never cut a covered replacement beat
  }
  if (paused_) {lastMs_=now;pauseStartMs_=now;}
  if (blinkActive_) {
    blinkActive_=false;
    diag_.blinking=false;
    ++diag_.mergedBlinkCount;
    lastCloseMs_=now;
  }
  sourceFrame_=frame_;sourceFrame_.replacementFrame=false;
  if (measuredAttention_) {
    // The captured source already contains measured pupil displacement. Start
    // any outgoing automatic/manual acquisition from zero added displacement.
    gazeFromX_=gazeFromY_=0;
    if (!gazeLocked_) gazeX_=gazeY_=0;
    gazeStartMs_=now;
  }
  if (pupilHandoff_ || (gazeLocked_ && (pose==PoseId::F03 || measuredAttention_))) {
    // Keep a pre-existing explicit gaze owner when entering measured motion,
    // and capture the displayed offsets once when handing that owner back to
    // an ordinary transition. The source already contains its pupil motion.
    capturePupilHandoff();
    gazeStartMs_=now;
  }
  measuredAttention_=false;
  sourcePose_=frame_.pose;
  diag_.source=sourcePose_;
  targetPose_=pose;
  clipIntensity_=clamp(std::isfinite(intensity)?intensity:.5F,0.0F,1.0F);
  Frame dest=authored(pose,clipIntensity_,targetLook_);
  gateRequired_=!compatible(sourceFrame_,dest);
  semanticClose_=(pose==PoseId::F07||pose==PoseId::R06||pose==PoseId::R07||pose==PoseId::C02);
  swapped_=false;socialBeat_=0;
  idleEndMs_=0;
  idleX_=idleY_=idleAspect_=idleSpacing_=0;
  ++diag_.clipCount;
  diag_.target=pose;
  // I-H semantic attention defaults. Explicit targets from the product/event
  // layer retain ownership; these never replace the cosmetic look.
  if (!gazeLocked_) {
    float gx=0,gy=0;
    switch (pose) {
      case PoseId::F12: gx=-.32F;gy=-.38F;break;
      case PoseId::F13: gx=0;gy=-.18F;break;
      case PoseId::F14: gx=0;gy=.12F;break;
      case PoseId::F11: gx=-.12F;gy=.62F;break;
      case PoseId::R09: gx=-.34F;gy=.46F;break;
      default: break;
    }
    const float previous=smooth(elapsed(now,gazeStartMs_,180));
    gazeFromX_=mix(gazeFromX_,gazeX_,previous);
    gazeFromY_=mix(gazeFromY_,gazeY_,previous);
    gazeX_=gx;gazeY_=gy;gazeStartMs_=now;
    diag_.gazeTargetX=gx;diag_.gazeTargetY=gy;
  }
  startStage(pose==PoseId::F03 && !gateRequired_ ? Stage::Peak : Stage::Anticipation,now);
  suppressBlinkUntilMs_=now+450;
}

void Engine::request(PoseId pose,float intensity,uint32_t nowMs) {
  const uint32_t now=nowMs?nowMs:lastMs_;
  if (!valid(pose))return;
  if (isPersistent(pose) && frame_.pose==pose &&
      (diag_.stage==Stage::Rest || diag_.stage==Stage::Sleep) &&
      targetLook_==lookId_)return;
  if (pose==PoseId::F06) sleeping_=true;
  else if (sleeping_) sleeping_=false;
  if (isPersistent(pose)) {
    if (pose!=PoseId::F06) persistentPose_=pose;
    temporaryActive_=false;
  } else {
    temporaryActive_=true;
    temporaryUntilMs_=now+reactionHold(pose);
  }
  resolveRequest(pose,intensity,now);
}
void Engine::setLook(uint8_t look) {
  if (look>=8 || look==targetLook_)return;
  if (diag_.stage==Stage::Gate || diag_.stage==Stage::Social) {
    pendingLook_=look;return;
  }
  targetLook_=look;
  resolveRequest(targetPose_,clipIntensity_,lastMs_);
}
void Engine::lookAt(float x,float y,uint32_t nowMs) {
  if (!std::isfinite(x)||!std::isfinite(y))return;
  const uint32_t now=nowMs?nowMs:lastMs_;
  if (targetPose_==PoseId::F03 || measuredAttention_ || pupilHandoff_)
    capturePupilHandoff();
  const float t=smooth(elapsed(now,gazeStartMs_,180));
  gazeFromX_=mix(gazeFromX_,gazeX_,t);gazeFromY_=mix(gazeFromY_,gazeY_,t);
  gazeX_=clamp(x,-1.0F,1.0F);gazeY_=clamp(y,-1.0F,1.0F);
  gazeStartMs_=now;gazeHoldMs_=now+420;
  gazeLocked_=true;
  diag_.gazeTargetX=gazeX_;diag_.gazeTargetY=gazeY_;
}
void Engine::capturePupilHandoff() {
  for (uint8_t i=0;i<2;++i) {
    pupilHandoffX_[i]=i<frame_.eyeCount?frame_.eyes[i].pupilX:0;
    pupilHandoffY_[i]=i<frame_.eyeCount?frame_.eyes[i].pupilY:0;
  }
  pupilHandoff_=true;
}
void Engine::centerGaze(uint32_t nowMs) {
  lookAt(0,0,nowMs);gazeLocked_=false;
}
void Engine::blink(uint32_t nowMs) {
  const uint32_t now=nowMs?nowMs:lastMs_;
  if (sleeping_ || blinkActive_ || !reached(now,suppressBlinkUntilMs_))return;
  if (targetPose_==PoseId::F07 || targetPose_==PoseId::R06 ||
      targetPose_==PoseId::R07 || targetPose_==PoseId::C02 ||
      targetPose_==PoseId::R08 || targetPose_==PoseId::F08 ||
      isSocial(targetPose_)) {scheduleBlink(now);return;}
  if (diag_.transitionActive) {
    if (gateRequired_) ++diag_.mergedBlinkCount;
    scheduleBlink(now);return;
  }
  if (lastCloseMs_ && now-lastCloseMs_<450) {scheduleBlink(now);return;}
  blinkActive_=true;blinkClosure_=Closure::Neutral;blinkStartMs_=now;
  diag_.closure=blinkClosure_;diag_.blinking=true;
  scheduleBlink(now);
}
void Engine::close(Closure kind,uint32_t nowMs) {
  const uint32_t now=nowMs?nowMs:lastMs_;
  if (kind==Closure::Neutral) {blink(now);return;}
  if (kind==Closure::Sleepy) {sleep(now);return;}
  request(kind==Closure::Happy?PoseId::C02:PoseId::C04,.5F,now);
  diag_.closure=kind;
}
void Engine::sleep(uint32_t nowMs) {
  const uint32_t now=nowMs?nowMs:lastMs_;
  sleeping_=true;
  blinkActive_=false;
  request(PoseId::F06,.5F,now);
  sleeping_=true;
}
void Engine::wake(uint32_t nowMs) {
  const uint32_t now=nowMs?nowMs:lastMs_;
  if (!sleeping_ && targetPose_!=PoseId::F06)return;
  sleeping_=false;
  persistentPose_=PoseId::F01;
  blinkActive_=false;
  request(PoseId::R10,.75F,now);
  suppressBlinkUntilMs_=now+1000;
}
void Engine::pause(bool paused) {
  if (paused_==paused)return;
  if (paused) pauseStartMs_=lastMs_;
  else {
    const uint32_t delta=lastMs_-pauseStartMs_;
    stageStartMs_+=delta;gazeStartMs_+=delta;idleStartMs_+=delta;
    idleEndMs_+=delta;blinkStartMs_+=delta;
    diag_.nextBlinkMs+=delta;diag_.nextIdleMs+=delta;
    suppressBlinkUntilMs_+=delta;temporaryUntilMs_+=delta;
    measuredStartMs_+=delta;
  }
  paused_=paused;diag_.paused=paused;
}
void Engine::restartClip(uint32_t nowMs) {
  const uint32_t now=nowMs?nowMs:lastMs_;
  if (targetPose_==PoseId::F03 && measuredAttention_) {
    // sourceFrame_ remains the original handoff, not the deformed final pose.
    blinkActive_=false;diag_.blinking=false;
    startStage(Stage::Peak,now);
    if (paused_) {lastMs_=now;pauseStartMs_=now;}
    return;
  }
  sourceFrame_=authored(sourcePose_,clipIntensity_,lookId_);
  swapped_=false;
  startStage(Stage::Anticipation,now);
}
void Engine::step(uint32_t nowMs) {
  const bool wasPaused=paused_;
  if (wasPaused) pause(false); // Exclude time spent paused before this step.
  update(nowMs);
  if (wasPaused) pause(true);
}

void Engine::evaluate(uint32_t now) {
  const PoseId target=targetPose_;
  const Frame dest=authored(target,clipIntensity_,targetLook_);
  const Stage stage=diag_.stage;
  frame_.replacementFrame=false;
  float t=0;
  const bool measured=target==PoseId::F03 && measuredAttention_;
  if (measured) {
    const uint32_t age=now-measuredStartMs_;
    const float handoff=elapsed(now,measuredStartMs_,140);
    // The handoff is a product adaptation; source channel timing begins at
    // request time and keeps its measured 1066.667ms duration and reversals.
    if (age>=1067 && stage!=Stage::Rest) startStage(Stage::Rest,now);
    blendGeometry(frame_,sourceFrame_,dest,handoff);
    frame_.coverage=mix(sourceFrame_.coverage,dest.coverage,smooth(handoff));
    frame_.replacementFrame=false;
    applyMeasuredAttention(frame_,age,clipIntensity_);
    t=clamp(age*1000.0F/MeasuredMotion::kAttentionDurationUs,0,1);
  } else switch(stage) {
    case Stage::Rest:
    case Stage::Sleep:
      frame_=dest;
      if (stage==Stage::Sleep) {
        const float cycle=static_cast<float>((now-stageStartMs_)%4200)/4200.0F;
        const float breath=cycle<.5F?smooth(cycle*2.0F):smooth((1.0F-cycle)*2.0F);
        for(uint8_t i=0;i<frame_.eyeCount;i++)frame_.eyes[i].height*=1.0F+.015F*breath;
      }
      if (isReaction(target) || isSocial(target))
        frame_.effectPhase=clamp(static_cast<float>(now-stageStartMs_)/1200.0F,0,1);
      if (target==PoseId::R01) {
        const float p=clamp(static_cast<float>(now-stageStartMs_)/1000.0F,0,1);
        const float wobble=std::sin(p*2.0F*kPi)*(1.0F-p)*5.0F;
        for(uint8_t i=0;i<frame_.eyeCount;i++) {
          frame_.eyes[i].x+=wobble;
          frame_.eyes[i].rotation+=(i%2?1.0F:-1.0F)*(1.0F-p)*2.0F;
        }
      }
      break;
    case Stage::Anticipation:
      t=elapsed(now,stageStartMs_,kTiming.attention);
      frame_=sourceFrame_;
      frame_.pose=t<.55F?PoseId::T01:PoseId::T02;
      for(uint8_t i=0;i<frame_.eyeCount;i++) {
        Eye& e=frame_.eyes[i];
        e.height*=1.0F-.12F*smooth(std::max(0.0F,(t-.48F)/.52F))*clipIntensity_;
        if (target==PoseId::R09) e.rotation+=(i%2?1:-1)*2.5F*t;
      }
      if (t>=1.0F)startStage(gateRequired_?Stage::Gate:Stage::Peak,now);
      break;
    case Stage::Gate: {
      const float duration=(target==PoseId::F06?kTiming.sleepClose:kTiming.gateClose);
      t=elapsed(now,stageStartMs_,duration);
      const float cover=smooth(t);
      frame_=swapped_?dest:sourceFrame_;
      frame_.pose=isSocial(target)?PoseId::T11:(semanticClose_?PoseId::T04:PoseId::T03);
      frame_.coverage=cover;
      frame_.effects=(isSocial(target)&&swapped_)?Flash:0;
      // Pupil occlusion reaches 100% BEFORE any topology replacement.
      for(uint8_t i=0;i<frame_.eyeCount;i++) {
        Eye& e=frame_.eyes[i];
        e.height=mix(e.height,(semanticClose_?.025F:.045F)*D,cover);
        e.pupilWidth*=1.0F-cover;e.pupilHeight*=1.0F-cover;
        e.lidTop=std::max(e.lidTop,cover*.5F);
        e.lidBottom=std::max(e.lidBottom,cover*.5F);
      }
      if (t>=1.0F && !swapped_) {
        swapped_=true;
        lookId_=targetLook_;
        frame_=dest;
        frame_.pose=isSocial(target)?PoseId::T11:PoseId::T04;
        frame_.coverage=1.0F;
        frame_.effects=isSocial(target)?Flash:0;
        frame_.replacementFrame=true;
        for(uint8_t i=0;i<frame_.eyeCount;i++) {
          frame_.eyes[i].height=(semanticClose_?.025F:.045F)*D;
          frame_.eyes[i].pupilWidth=frame_.eyes[i].pupilHeight=0;
          frame_.eyes[i].lidTop=frame_.eyes[i].lidBottom=.5F;
        }
        ++diag_.topologySwapCount;
        lastCloseMs_=now;
        diag_.stageProgress=1;
        return; // a complete covered swap frame, even after a long host stall
      }
      if (swapped_ && now-stageStartMs_>=duration+kTiming.gateHold)
        startStage(isSocial(target)?Stage::Social:Stage::Peak,now);
      break;
    }
    case Stage::Social:
      t=elapsed(now,stageStartMs_,kTiming.social);
      frame_=dest;
      frame_.effectPhase=t;
      if (t<.25F && target!=PoseId::S03) {
        frame_.pose=PoseId::T10;
        scaleAroundPair(frame_,.93F,.96F);
      } else if (target==PoseId::S01 && t>.55F && t<.82F) {
        // Mixed exchange beat is geometry-only. A motif/look topology change
        // would need another covered gate; never sneak one into this interval.
        frame_.pose=PoseId::S02;
        for(uint8_t i=0;i<frame_.eyeCount;i++) {
          const float side=i<2?1.07F:.93F;
          frame_.eyes[i].width*=side;
          frame_.eyes[i].height*=side;
          frame_.eyes[i].y+=i<2?-4.0F:4.0F;
        }
      } else if (t<.48F && target==PoseId::S03) {
        frame_.pose=PoseId::T12;frame_.effects|=Collision;
      }
      if (t>=1.0F)startStage(Stage::Settle,now);
      break;
    case Stage::Peak:
      t=elapsed(now,stageStartMs_,kTiming.peak);
      if (gateRequired_) {
        frame_=dest;
        frame_.coverage=1.0F-smooth(t);
        frame_.pose=PoseId::T07;
        for(uint8_t i=0;i<frame_.eyeCount;i++) {
          Eye& e=frame_.eyes[i];
          e.height=mix(.045F*D,e.height,t);
          e.pupilWidth*=smooth(t);e.pupilHeight*=smooth(t);
        }
      } else {
        blendGeometry(frame_,sourceFrame_,dest,t);
        if (target==PoseId::R09) frame_.pose=PoseId::T06;
      }
      frame_.effectPhase=t*.35F;
      if (t>=1.0F)startStage(Stage::Overshoot,now);
      break;
    case Stage::Overshoot:
      t=elapsed(now,stageStartMs_,kTiming.overshoot);
      frame_=dest;
      frame_.pose=(target==PoseId::F08?PoseId::T08:PoseId::T07);
      scaleAroundPair(frame_,1.0F+overshootFor(target,clipIntensity_)*smooth(t),
                      1.0F+spacingOvershootFor(target,clipIntensity_)*smooth(t));
      frame_.effectPhase=.35F+.2F*t;
      if (t>=1.0F)startStage(Stage::Settle,now);
      break;
    case Stage::Settle:
      t=elapsed(now,stageStartMs_,target==PoseId::R10?kTiming.wakeSettle:kTiming.settle);
      frame_=dest;
      frame_.pose=t<.65F?PoseId::T09:target;
      // One approach from overshoot plus one tiny correction; no spring loop.
      {
        const float amp=overshootFor(target,clipIntensity_)*(1.0F-smooth(t));
        const float spacingAmp=spacingOvershootFor(target,clipIntensity_)*(1.0F-smooth(t));
        const float correction=t>.72F ? -.018F*std::sin((t-.72F)/.28F*kPi) : 0;
        scaleAroundPair(frame_,1.0F+amp+correction,1.0F+spacingAmp);
      }
      frame_.effectPhase=.55F+.45F*t;
      if (t>=1.0F)startStage(Stage::Rest,now);
      break;
    case Stage::Blink: break;
  }
  if (diag_.stage==stage) {
    diag_.stageProgress=t;
    if(stage==Stage::Settle)diag_.settleProgress=t;
  }

  // Gaze is eye-local and independent from outer body geometry. Two pupils
  // acquire at different delays; outer eyes follow only after established gaze.
  const float idleDuration=idleEndMs_>idleStartMs_?
      static_cast<float>(idleEndMs_-idleStartMs_):1.0F;
  const float idleIn=(idleEvent_==0?95.0F:idleEvent_==1?220.0F:260.0F);
  const float idleOut=(idleEvent_==0?140.0F:idleEvent_==1?250.0F:280.0F);
  const float idleAge=static_cast<float>(now-idleStartMs_);
  const float idleGain=idleEndMs_ && now>=idleStartMs_ && !reached(now,idleEndMs_)?
      smooth(idleAge/idleIn)*smooth((idleDuration-idleAge)/idleOut):0.0F;
  if (frame_.family!=Family::Arc && frame_.family!=Family::Slit &&
      frame_.family!=Family::Collage && !sleeping_ && !measured &&
      stage!=Stage::Gate && stage!=Stage::Social) {
    const float gazeDistance=std::max(std::fabs(gazeX_-gazeFromX_),
                                      std::fabs(gazeY_-gazeFromY_));
    for(uint8_t i=0;i<frame_.eyeCount;i++) {
      Eye& e=frame_.eyes[i];
      const float lag=(i%2==0?0.0F:55.0F);
      const float u=clamp((static_cast<float>(now-gazeStartMs_)-lag)/165.0F,0,1);
      // One small acquisition correction (I-H), never a looping spring.
      const float progress=u<.72F ? 1.04F*smooth(u/.72F):
        mix(1.04F,1.0F,smooth((u-.72F)/.28F));
      const float gain=(i%2==0?1.08F:.92F);
      const float gx=mix(gazeFromX_,gazeX_,progress)*gain;
      const float gy=mix(gazeFromY_,gazeY_,progress)*gain;
      const float acquire=clamp((static_cast<float>(now-gazeStartMs_)-90)/170.0F,0,1);
      e.pupilX+=gx*e.width*.20F + idleX_*idleGain;
      e.pupilY+=gy*e.height*.18F + idleY_*idleGain;
      if (gazeDistance>.35F && stage==Stage::Rest) {
        e.x+=gx*11.0F*smooth(acquire);e.y+=gy*8.0F*smooth(acquire);
      }
      clampPupil(e);
    }
  }

  if (stage==Stage::Rest && !sleeping_ && !measured) {
    for(uint8_t i=0;i<frame_.eyeCount;i++) {
      frame_.eyes[i].height*=1.0F+idleAspect_*idleGain;
      frame_.eyes[i].x+=(i%2?idleSpacing_:-idleSpacing_)*idleGain;
    }
  }
  if (pupilHandoff_ && frame_.family!=Family::Arc && frame_.family!=Family::Slit &&
      frame_.family!=Family::Collage && stage!=Stage::Gate && stage!=Stage::Social) {
    const uint32_t age=now-gazeStartMs_;
    for(uint8_t i=0;i<frame_.eyeCount;++i) {
      Eye& e=frame_.eyes[i];
      const uint8_t side=i%2;
      const float lag=side==0?0.0F:55.0F;
      const float u=clamp((static_cast<float>(age)-lag)/165.0F,0,1);
      const float progress=u<.72F?1.04F*smooth(u/.72F):
          mix(1.04F,1.0F,smooth((u-.72F)/.28F));
      const float gain=side==0?1.08F:.92F;
      // Explicit ownership replaces automatic pupil displacement; it never
      // adds a second copy of gaze to the already displayed source frame.
      // centerGaze releases smoothly back to the current automatic channels.
      const float targetX=gazeLocked_?
          (side==0?1.0F:-1.0F)*e.width*.04F+gazeX_*gain*e.width*.20F:e.pupilX;
      const float targetY=gazeLocked_?gazeY_*gain*e.height*.18F:e.pupilY;
      e.pupilX=mix(pupilHandoffX_[side],targetX,progress);
      e.pupilY=mix(pupilHandoffY_[side],targetY,progress);
    }
    if (!gazeLocked_ && age>=220) pupilHandoff_=false;
  }
  if (blinkActive_) {
    const uint32_t dt=now-blinkStartMs_;
    const uint32_t c=kTiming.blinkClose,h=kTiming.blinkHold,o=kTiming.blinkOpen;
    float cover=0;
    if(dt<c)cover=smooth(static_cast<float>(dt)/c);
    else if(dt<c+h)cover=1;
    else if(dt<c+h+o)cover=1-smooth(static_cast<float>(dt-c-h)/o);
    else {blinkActive_=false;diag_.blinking=false;lastCloseMs_=now;}
    if(blinkActive_) {
      frame_.pose=PoseId::C01;frame_.coverage=cover;
      for(uint8_t i=0;i<frame_.eyeCount;i++) {
        frame_.eyes[i].height*=1.0F-.92F*cover;
        frame_.eyes[i].pupilWidth*=1.0F-cover;
        frame_.eyes[i].pupilHeight*=1.0F-cover;
      }
    }
  }
  frame_.lookId=lookId_;
  for(uint8_t i=0;i<frame_.eyeCount;i++) {
    frame_.eyes[i].rotation=clamp(frame_.eyes[i].rotation,-6.0F,6.0F);
    clampPupil(frame_.eyes[i]);
  }
}

void Engine::update(uint32_t nowMs) {
  if(paused_){lastMs_=nowMs;return;}
  lastMs_=nowMs;
  if (temporaryActive_ && reached(nowMs,temporaryUntilMs_) &&
      diag_.stage==Stage::Rest && targetPose_!=persistentPose_) {
    temporaryActive_=false;
    resolveRequest(persistentPose_,clipIntensity_,nowMs);
  }
  if (diag_.stage==Stage::Rest && !sleeping_ && !idleFrozen_ && idleEnabled_ &&
      !gazeLocked_ && !measuredAttention_ && reached(nowMs,diag_.nextIdleMs)) {
    // State weights prevent a generic wander from intruding on cognition.
    if (targetPose_==PoseId::F14) idleEvent_=(random()%5==0)?2:4;
    else if (targetPose_==PoseId::F13) idleEvent_=(random()%4==0)?0:4;
    else if (targetPose_==PoseId::F12) idleEvent_=(random()%6==0)?0:4;
    else idleEvent_=static_cast<uint8_t>(random()%5);
    idleStartMs_=nowMs;
    const uint32_t duration=(idleEvent_==0?360:idleEvent_==1?1100:
                              idleEvent_==2?1200:idleEvent_==3?350:500);
    idleEndMs_=nowMs+duration;
    const float sign=(random()&1)?1.0F:-1.0F;
    idleX_=idleEvent_==0?sign*(randomRange(1,3)*.01F)*(.30F*D):
            idleEvent_==1?sign*(randomRange(8,24)*.01F)*(.065F*D):0;
    idleY_=idleEvent_<=1?((random()&1)?1.0F:-1.0F)*
            (idleEvent_==0?2.0F:4.0F):0;
    idleAspect_=idleEvent_==2?sign*(targetPose_==PoseId::F14?.010F:.018F):0;
    idleSpacing_=idleEvent_==3?sign*D*.012F:0;
    scheduleIdle(nowMs+duration);
  }
  if (idleEndMs_ && reached(nowMs,idleEndMs_)) {
    idleX_=idleY_=idleAspect_=idleSpacing_=0;idleEndMs_=0;
  }
  if (diag_.stage==Stage::Rest && !sleeping_ && idleEnabled_ &&
      reached(nowMs,diag_.nextBlinkMs))blink(nowMs);
  evaluate(nowMs);
  if(diag_.stage==Stage::Rest || diag_.stage==Stage::Sleep) {
    if(pendingLook_<8){const auto next=pendingLook_;pendingLook_=255;setLook(next);}
    else if(pendingPose_!=PoseId::Count){
      const auto next=pendingPose_;const float intensity=pendingIntensity_;
      pendingPose_=PoseId::Count;
      request(next,intensity,nowMs);
    }
  }
  diag_.sleeping=sleeping_;
  diag_.blinking=blinkActive_;
  diag_.idleEnabled=idleEnabled_;
  diag_.idleFrozen=idleFrozen_;
  diag_.paused=paused_;
}
Diagnostics Engine::diagnostics() const{return diag_;}

} // namespace FaceMotion
