import 'package:flutter/widgets.dart';

/// Keeps a conversation attached to its end across viewport changes. History
/// readers keep their offset; only an explicit jump/send reattaches the tail.
class ChatScrollController extends ScrollController {
  bool followTail = true;
  bool animating = false;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      _ChatScrollPosition(
        owner: this,
        physics: physics,
        context: context,
        oldPosition: oldPosition,
      );
}

class _ChatScrollPosition extends ScrollPositionWithSingleContext {
  _ChatScrollPosition({
    required this.owner,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final ChatScrollController owner;
  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (owner.followTail &&
        !owner.animating &&
        hasPixels &&
        pixels != maxScrollExtent) {
      // Layout correction, not a delayed scroll based on an estimated old
      // extent. Flutter repeats layout if lazy child measurement changes it.
      correctPixels(maxScrollExtent);
      return false;
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
