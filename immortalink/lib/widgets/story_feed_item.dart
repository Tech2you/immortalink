import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'heiro_surface.dart';

class StoryFeedItem extends StatefulWidget {
  final Widget author;
  final String title;
  final String body;
  final List<Widget> photos;
  final List<Widget> recordings;
  final VoidCallback onOpen;

  const StoryFeedItem({
    super.key,
    required this.author,
    required this.title,
    required this.body,
    required this.photos,
    required this.recordings,
    required this.onOpen,
  });

  @override
  State<StoryFeedItem> createState() => _StoryFeedItemState();
}

class _StoryFeedItemState extends State<StoryFeedItem> {
  int _photo = 0;
  bool _allRecordings = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.photos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: widget.author,
        ),
        if (widget.title.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: widget.onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        if (widget.body.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: ExpandableStory(text: widget.body),
          ),
        if (count > 0) ...[
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: heiroIce,
                  child: PageView(
                    onPageChanged: (value) => setState(() => _photo = value),
                    children: widget.photos,
                  ),
                ),
                if (count > 1)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .62),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: Text(
                          '${(_photo + 1).clamp(1, count)}/$count',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (count > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Semantics(
                label: 'Photo ${_photo + 1} of $count',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(count.clamp(0, 5), (index) {
                    final start = (_photo - 2).clamp(
                      0,
                      (count - 5).clamp(0, count),
                    );
                    return Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index + start == _photo
                            ? heiroBlue
                            : const Color(0xFFD1DEE5),
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
        if (widget.recordings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              children: [
                ...(_allRecordings
                    ? widget.recordings
                    : widget.recordings.take(1)),
                if (widget.recordings.length > 1)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _allRecordings = !_allRecordings),
                    icon: Icon(
                      _allRecordings ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: Text(
                      _allRecordings
                          ? 'Fewer recordings'
                          : '${widget.recordings.length - 1} more recording${widget.recordings.length == 2 ? '' : 's'}',
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const Divider(height: 1),
      ],
    );
  }
}

class ExpandableStory extends StatefulWidget {
  final String text;
  const ExpandableStory({super.key, required this.text});

  @override
  State<ExpandableStory> createState() => _ExpandableStoryState();
}

class _ExpandableStoryState extends State<ExpandableStory> {
  bool _expanded = false;
  late final TapGestureRecognizer _toggle = TapGestureRecognizer()
    ..onTap = () => setState(() => _expanded = !_expanded);

  @override
  void dispose() {
    _toggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(const TextStyle(fontSize: 16, height: 1.45, color: heiroInk));
    const linkStyle = TextStyle(color: heiroBlue, fontWeight: FontWeight.w600);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 3,
        );
        bool fits(String text) {
          painter.text = TextSpan(
            style: style,
            children: [
              TextSpan(text: text),
              const TextSpan(text: '... See more', style: linkStyle),
            ],
          );
          painter.layout(maxWidth: constraints.maxWidth);
          return !painter.didExceedMaxLines;
        }

        painter.text = TextSpan(text: widget.text, style: style);
        painter.layout(maxWidth: constraints.maxWidth);
        final overflowing = painter.didExceedMaxLines;
        if (!overflowing) {
          painter.dispose();
          return Text(widget.text, style: style);
        }
        var visible = widget.text;
        if (!_expanded) {
          // Measure the link too, so large text never pushes it under the photo.
          final characters = widget.text.characters.toList();
          var low = 0;
          var high = characters.length;
          while (low < high) {
            final middle = (low + high + 1) ~/ 2;
            if (fits(characters.take(middle).join())) {
              low = middle;
            } else {
              high = middle - 1;
            }
          }
          visible = characters.take(low).join().trimRight();
        }
        painter.dispose();
        return Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(text: visible),
              TextSpan(
                text: _expanded ? '  See less' : '... See more',
                style: linkStyle,
                recognizer: _toggle,
              ),
            ],
          ),
        );
      },
    );
  }
}
