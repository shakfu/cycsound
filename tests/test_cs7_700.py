"""Host API changes in Csound 7.0.0."""

import pytest

import cycsound


@pytest.fixture
def instance():
    # readline claims stdin for the whole process until deinit, even in
    # host-input mode, so each instance must release it before the next test.
    made = []

    def make(orc=None):
        made.append(_instance(orc))
        return made[-1]

    yield make
    for c in made:
        c.reset()


def _instance(orc=None):
    c = cycsound.Csound()
    for opt in ("-n", "-d", "-m0"):
        c.set_option(opt)
    if orc is not None:
        assert c.compile_orc(orc) == 0
    return c


READLINE_ORC = """
ksmps = 1
chn_k "status", 2
chn_S "line", 2
instr 1
  Sline, kstatus readline "name? "
  if (kstatus == 1) then
    chnset Sline, "line"
    chnset kstatus, "status"
  endif
endin
"""


def _perform_until_status(c, n=64):
    for _ in range(n):
        assert c.perform_ksmps() == 0
        if c.get_control_channel("status") == 1.0:
            return


def test_readline_callback_submit(instance):
    c = instance(READLINE_ORC)
    calls = []

    def on_request(request_id, prompt):
        calls.append((request_id, prompt))
        if prompt is not None:
            assert c.readline_submit(request_id, "from callback") == 0

    c.set_readline_callback(on_request)
    c.event_string("i 1 0 1")
    assert c.start() == 0
    _perform_until_status(c)
    assert c.get_string_channel("line") == "from callback"
    assert calls[0][0] != 0
    assert calls[0][1] == "name? "
    # The request closes on successful submission.
    assert (calls[0][0], None) in calls


def test_readline_submit_stale_request(instance):
    c = instance(READLINE_ORC)
    ids = []
    c.set_readline_callback(lambda rid, prompt: ids.append(rid))
    c.event_string("i 1 0 1")
    assert c.start() == 0
    for _ in range(4):
        c.perform_ksmps()
    assert ids
    assert c.readline_submit(ids[0] + 1000, "nobody asked") != 0
    assert c.readline_submit(ids[0], "bad\x01byte") != 0
    assert c.readline_submit(ids[0], "ok") == 0
    assert c.readline_submit(ids[0], "again") != 0  # closed by the first


def test_readline_callback_type_check_and_removal():
    c = _instance()
    with pytest.raises(TypeError):
        c.set_readline_callback(42)
    c.set_readline_callback(lambda rid, prompt: None)
    c.set_readline_callback(None)


def test_perform_ksmps_reentry_is_negative():
    # 7.0.0 returns CSOUND_ERROR for performance calls inside a render pass.
    # outvalue also fires at init, outside the render pass; keep the
    # k-rate (in-pass) results only.
    c = _instance('chn_k "out", 2\ninstr 1\noutvalue "out", k(1)\nendin\n')
    results = []
    depth = [0]

    def on_output(name, value):
        if depth[0]:
            return
        depth[0] += 1
        results.append(c.perform_ksmps())
        depth[0] -= 1

    c.set_output_channel_callback(on_output)
    c.event_string("i 1 0 0.01")
    assert c.start() == 0
    for _ in range(4):
        c.perform_ksmps()
    assert any(r < 0 for r in results)


def test_perform_ksmps_before_start_is_negative():
    c = _instance()
    assert c.perform_ksmps() < 0
