// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The software keyboard, and the key bar a terminal needs above it.
//
// iOS only produces UIPress events for a HARDWARE keyboard. Nothing a person
// types on the on-screen keyboard arrives that way: the system delivers it to
// whichever first responder implements UIKeyInput, as edited text. So a
// framework that reads keys — as this one does, through FocusNode.onKeyData —
// sees precisely nothing from the on-screen keyboard, and the app is usable
// only on a simulator borrowing the Mac's keys. That was the state of the iOS
// port until this file: it renders, it connects, and on a real phone there is
// no way to type into it.
//
// The fix is not the flutter/textinput channel. That is the right answer for a
// text FIELD — the engine's FlutterTextInputPlugin owns an edit buffer, and the
// framework and the platform reconcile editing state, selection and composing
// regions on every keystroke. A terminal wants none of it: it wants the
// keystroke. Autocorrect rewriting a shell command, and backspace deleting from
// a buffer the remote side does not know about, are the two failure modes that
// arrangement produces, and both are worse than no keyboard at all. Every
// native terminal on this platform takes the UIKeyInput route instead, and so
// does this.
//
// What comes out is a keystroke, not an edit: `insertText:` becomes the
// characters, `deleteBackward` becomes a backspace keysym, and the bar's keys
// become the keysym they name. The Swift side turns each into a KeyData and
// hands it to the same FocusManager the engine's own key events go through, so
// nothing downstream can tell the difference — TerminalInput maps it to bytes
// exactly as it maps a hardware key.
//
// The bar is not decoration. A phone keyboard has no Escape, no Control, no
// Tab and no arrows, and those are most of how anyone drives a TUI: Escape
// interrupts, Ctrl+C signals, Tab completes, Shift+Tab cycles Claude Code's
// permission mode, and the arrows are history. Without the bar the keyboard
// alone gets you typing and nothing else.

#import <UIKit/UIKit.h>

#import "include/FlutterUIKitBridge.h"

static FlUIKitKeyCallback g_key_cb = NULL;
static void* g_key_user = NULL;

// Defined below, next to the note on why the folding happens here at all.
static NSString* FlUIKitApplyControl(NSString* text);

// MARK: - The first responder

// Zero-sized and never hit-tested, so it takes no touches from the Flutter
// view it lives inside; first-responder status does not depend on either.
//
// It is a subview of the FlutterViewController's view ON PURPOSE. UIKit walks
// the responder chain from the first responder up through its superviews, so
// sitting under the Flutter view is what keeps HARDWARE keys working while
// this view holds the responder: a UIPress this view does not handle continues
// up into FlutterView and reaches the engine on its usual path. Parked as a
// sibling instead, the chain skips the engine entirely and attaching a Magic
// Keyboard stops typing anything.
@interface FlUIKitKeyInputView : UIView <UIKeyInput>
@property(nonatomic, assign) BOOL ctrlArmed;
@property(nonatomic, assign) BOOL shiftArmed;
@end

@implementation FlUIKitKeyInputView {
  UIView* _accessory;
  UIButton* _ctrlButton;
  UIButton* _shiftButton;
}

- (BOOL)canBecomeFirstResponder {
  return YES;
}

// MARK: UIKeyInput

// Always YES. A terminal has no edit buffer for UIKit to reason about, and
// answering NO makes iOS stop sending deleteBackward once it believes the
// field is empty — backspace would work until the first one and then die.
- (BOOL)hasText {
  return YES;
}

- (void)insertText:(NSString*)text {
  if (text.length == 0) {
    return;
  }
  // Return arrives as a newline from the on-screen keyboard. Send it as the
  // Enter keysym rather than as text, so it goes through the same CR mapping
  // as a hardware Return instead of writing a raw 0x0A the shell will not
  // accept as a line ending.
  if ([text isEqualToString:@"\n"]) {
    [self emitKeysym:kFlUIKitKeyEnter];
    return;
  }

  NSString* out = text;
  if (self.ctrlArmed) {
    out = FlUIKitApplyControl(text);
    [self setCtrlArmed:NO];
  }
  if (self.shiftArmed) {
    // Shift is only meaningful here for the chords the bar exists to send
    // (Shift+Tab); the keyboard has already applied it to any letter.
    [self setShiftArmed:NO];
  }
  if (g_key_cb != NULL) {
    g_key_cb(g_key_user, out.UTF8String, 0, 0);
  }
}

- (void)deleteBackward {
  [self emitKeysym:kFlUIKitKeyBackspace];
}

- (void)emitKeysym:(int32_t)keysym {
  if (g_key_cb == NULL) {
    return;
  }
  int32_t shift = self.shiftArmed ? 1 : 0;
  if (self.ctrlArmed) {
    // A control chord on a named key: there is no character to fold the
    // modifier into, so pass it through as a keysym with ctrl noted. Only
    // Ctrl+arrows and the like reach here; Ctrl+letter went through
    // insertText:.
    [self setCtrlArmed:NO];
  }
  if (self.shiftArmed) {
    [self setShiftArmed:NO];
  }
  g_key_cb(g_key_user, NULL, keysym, shift);
}

// MARK: UITextInputTraits
//
// Every one of these is load-bearing for a terminal. Autocorrect and smart
// punctuation rewrite what was typed — a smart quote in a shell command is a
// syntax error, and an autocorrected flag is a different flag. Autocapitalize
// turns `git` into `Git`. They are on by default, so each has to be refused.

- (UITextAutocorrectionType)autocorrectionType {
  return UITextAutocorrectionTypeNo;
}

- (UITextAutocapitalizationType)autocapitalizationType {
  return UITextAutocapitalizationTypeNone;
}

- (UITextSpellCheckingType)spellCheckingType {
  return UITextSpellCheckingTypeNo;
}

- (UITextSmartQuotesType)smartQuotesType {
  return UITextSmartQuotesTypeNo;
}

- (UITextSmartDashesType)smartDashesType {
  return UITextSmartDashesTypeNo;
}

- (UITextSmartInsertDeleteType)smartInsertDeleteType {
  return UITextSmartInsertDeleteTypeNo;
}

- (UIKeyboardAppearance)keyboardAppearance {
  return UIKeyboardAppearanceDark;
}

// Without this the Return key greys out whenever UIKit thinks the field is
// empty, which for a terminal is most of the time.
- (BOOL)enablesReturnKeyAutomatically {
  return NO;
}

// MARK: The accessory bar

- (UIView*)inputAccessoryView {
  if (_accessory != nil) {
    return _accessory;
  }

  UIInputView* bar =
      [[UIInputView alloc] initWithFrame:CGRectMake(0, 0, 0, 44)
                          inputViewStyle:UIInputViewStyleKeyboard];

  UIStackView* stack = [[UIStackView alloc] init];
  stack.axis = UILayoutConstraintAxisHorizontal;
  stack.distribution = UIStackViewDistributionFillEqually;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 2;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [bar addSubview:stack];

  // Pinned to the safe area, not the bar's edges: on a home-indicator phone
  // the accessory sits above the indicator and the trailing button would
  // otherwise land under it.
  UILayoutGuide* safe = bar.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [stack.topAnchor constraintEqualToAnchor:bar.topAnchor constant:2],
    // The BOTTOM goes to the safe area, not the bar's own edge. An accessory
    // view extends under the home indicator when the keyboard is down, so
    // pinning to the edge puts the buttons beneath it — tappable in theory,
    // and sitting under a system control in practice.
    [stack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-2],
    [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:4],
    [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-4],
  ]];

  [stack addArrangedSubview:[self barButton:@"esc" action:@selector(tapEsc)]];
  _ctrlButton = [self barButton:@"ctrl" action:@selector(tapCtrl)];
  [stack addArrangedSubview:_ctrlButton];
  [stack addArrangedSubview:[self barButton:@"tab" action:@selector(tapTab)]];
  _shiftButton = [self barButton:@"⇧" action:@selector(tapShift)];
  [stack addArrangedSubview:_shiftButton];
  [stack addArrangedSubview:[self barButton:@"←" action:@selector(tapLeft)]];
  [stack addArrangedSubview:[self barButton:@"↓" action:@selector(tapDown)]];
  [stack addArrangedSubview:[self barButton:@"↑" action:@selector(tapUp)]];
  [stack addArrangedSubview:[self barButton:@"→" action:@selector(tapRight)]];
  [stack addArrangedSubview:[self barButton:@"⌄" action:@selector(tapDismiss)]];

  _accessory = bar;
  return _accessory;
}

- (UIButton*)barButton:(NSString*)title action:(SEL)action {
  UIButton* b = [UIButton buttonWithType:UIButtonTypeSystem];
  [b setTitle:title forState:UIControlStateNormal];
  b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
  [b setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
  b.backgroundColor = [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.35];
  b.layer.cornerRadius = 5;
  [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  return b;
}

// A modifier is armed until the next key rather than held, because there is no
// way to hold one and type on a touch screen at the same time.
- (void)setCtrlArmed:(BOOL)armed {
  _ctrlArmed = armed;
  [self refreshModifierButton:_ctrlButton armed:armed];
}

- (void)setShiftArmed:(BOOL)armed {
  _shiftArmed = armed;
  [self refreshModifierButton:_shiftButton armed:armed];
}

- (void)refreshModifierButton:(UIButton*)button armed:(BOOL)armed {
  if (button == nil) {
    return;
  }
  button.backgroundColor =
      armed ? UIColor.systemBlueColor
            : [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.35];
  [button setTitleColor:armed ? UIColor.whiteColor : UIColor.labelColor
               forState:UIControlStateNormal];
}

- (void)tapEsc {
  [self emitKeysym:kFlUIKitKeyEscape];
}
- (void)tapTab {
  [self emitKeysym:kFlUIKitKeyTab];
}
- (void)tapLeft {
  [self emitKeysym:kFlUIKitKeyLeft];
}
- (void)tapRight {
  [self emitKeysym:kFlUIKitKeyRight];
}
- (void)tapUp {
  [self emitKeysym:kFlUIKitKeyUp];
}
- (void)tapDown {
  [self emitKeysym:kFlUIKitKeyDown];
}
- (void)tapCtrl {
  [self setCtrlArmed:!self.ctrlArmed];
}
- (void)tapShift {
  [self setShiftArmed:!self.shiftArmed];
}
- (void)tapDismiss {
  [self resignFirstResponder];
}

@end

// MARK: - Control folding

// Ctrl+letter is a control code, and by the time TerminalInput sees a key the
// modifier is expected to be folded into the character already — that is how a
// hardware Ctrl+C arrives as 0x03. Do the same here so the two paths produce
// identical bytes.
static NSString* FlUIKitApplyControl(NSString* text) {
  if (text.length == 0) {
    return text;
  }
  unichar c = [text characterAtIndex:0];
  if (c >= 'a' && c <= 'z') {
    return [NSString stringWithFormat:@"%C", (unichar)(c - 'a' + 1)];
  }
  if (c >= 'A' && c <= 'Z') {
    return [NSString stringWithFormat:@"%C", (unichar)(c - 'A' + 1)];
  }
  // The handful outside the letters that have long-standing control codes.
  switch (c) {
    case '[':
      return @"\x1B";
    case '\\':
      return @"\x1C";
    case ']':
      return @"\x1D";
    case '_':
    case '/':
      return @"\x1F";
    case ' ':
    case '@':
      return @"\0";
    default:
      return text;
  }
}

// MARK: - C entry points

static FlUIKitKeyInputView* g_key_view = NULL;

void fluikit_keyboard_attach(void* flutter_view) {
  if (g_key_view != NULL || flutter_view == NULL) {
    return;
  }
  UIView* host = (__bridge UIView*)flutter_view;
  FlUIKitKeyInputView* view = [[FlUIKitKeyInputView alloc] initWithFrame:CGRectZero];
  [host addSubview:view];
  g_key_view = view;
}

void fluikit_keyboard_set_callback(FlUIKitKeyCallback cb, void* user) {
  g_key_cb = cb;
  g_key_user = user;
}

void fluikit_keyboard_show(void) {
  if (g_key_view != NULL) {
    [g_key_view becomeFirstResponder];
  }
}

void fluikit_keyboard_hide(void) {
  if (g_key_view != NULL) {
    [g_key_view resignFirstResponder];
  }
}

bool fluikit_keyboard_visible(void) {
  return g_key_view != NULL && g_key_view.isFirstResponder;
}
