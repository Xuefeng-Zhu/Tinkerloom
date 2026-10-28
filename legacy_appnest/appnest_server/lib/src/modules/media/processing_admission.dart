/// Processing capacity belongs to the server process, not individual assets.
/// Reject excess work before retrieving originals; never queue byte buffers.
class ProcessingAdmission {
  final int maxConcurrent, maxPerActor;
  var _active = 0;
  final _actors = <String, int>{};
  ProcessingAdmission({this.maxConcurrent = 2, this.maxPerActor = 1});

  void Function()? acquire(String actor) {
    final count = _actors[actor] ?? 0;
    if (_active >= maxConcurrent || count >= maxPerActor) return null;
    _active++;
    _actors[actor] = count + 1;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _active--;
      final remaining = _actors[actor]! - 1;
      if (remaining == 0) {
        _actors.remove(actor);
      } else {
        _actors[actor] = remaining;
      }
    };
  }
}
