"""Opcodes as host-run unit generators (ugen.h)."""

import gc
import math

import pytest

import cycsound
from cycsound import UgenArgType as T

KSMPS = 16
SR = 48000


@pytest.fixture
def csound():
    c = cycsound.Csound()
    for opt in ("-n", "-d", "-m0", f"--ksmps={KSMPS}", f"--sample-rate={SR}"):
        c.set_option(opt)
    assert c.compile_orc("instr 1\nendin\n") == 0
    assert c.start() == 0
    return c


@pytest.fixture
def factory(csound):
    return csound.ugen_factory()


def _oscils(factory, amp=1.0, freq=1000.0):
    u = factory.new_ugen("oscils", "a", "iiio")
    for i, v in enumerate((amp, freq, 0.0, 0.0)):
        u.set_value(i, v)
    return u


def test_factory_requires_start():
    with pytest.raises(RuntimeError):
        cycsound.Csound().ugen_factory()


def test_list_and_find_opcodes(factory):
    ops = factory.list_opcodes()
    assert ("oscils", "a", "iiio") in ops
    assert factory.find_opcode("oscils", "a", "iiio")
    assert factory.find_opcode("oscils")  # None types match any entry
    assert not factory.find_opcode("oscils", "k", "iiio")
    assert not factory.find_opcode("no_such_opcode")


def test_new_ugen_requires_exact_entry(factory):
    with pytest.raises(ValueError):
        factory.new_ugen("oscils", "k", "iiio")
    with pytest.raises(ValueError):
        factory.new_ugen("no_such_opcode", "a", "")


def test_query_counts_and_types(factory):
    u = factory.new_ugen("oscils", "a", "iiio")
    assert (u.get_out_count(), u.get_in_count()) == (1, 4)
    assert u.get_out_type(0) == T.A
    assert [u.get_in_type(i) for i in range(4)] == [T.I] * 4
    assert (u.opname, u.outtypes, u.intypes) == ("oscils", "a", "iiio")
    # A var-arg parameter expands to UGEN_MAX_VAR_ARGS (8) slots.
    assert factory.new_ugen("linsegr", "k", "iim").get_in_count() == 2 + 8
    with pytest.raises(IndexError):
        u.get_in_var(4)
    with pytest.raises(IndexError):
        u.get_out_type(-1)


def test_init_perform_oscils(factory):
    u = _oscils(factory, amp=0.5, freq=SR / 8)
    assert u.init() == 0
    assert u.perform() == 0
    out = u.get_out_var(0)
    assert out.type == T.A
    assert out.size == KSMPS * cycsound.get_size_of_cs_float()
    samples = out.samples
    assert len(samples) == KSMPS
    # oscils: amp * sin(2 pi f n / sr) from phase 0.
    expected = [0.5 * math.sin(2 * math.pi * n / 8) for n in range(KSMPS)]
    assert samples == pytest.approx(expected, abs=1e-6)


def test_var_type_guards(factory):
    u = _oscils(factory)
    with pytest.raises(TypeError):
        u.get_out_var(0).value  # a-rate has no scalar value
    with pytest.raises(TypeError):
        u.get_in_var(0).string
    with pytest.raises(ValueError):
        u.get_out_var(0).samples = [0.0] * (KSMPS - 1)
    assert u.get_in_var(1).value == 1000.0
    assert u.get_in_var(1).data_address != 0


def test_wiring_and_standalone_var(factory):
    osc = _oscils(factory, amp=1.0, freq=SR / 8)
    mul = factory.new_ugen("##mul.ak", "a", "ak")
    gain = factory.new_var(T.K)
    gain.value = 0.25
    mul.set_input_var(0, osc.get_out_var(0))
    mul.set_input_var(1, gain)
    # The wired input shares the source's data.
    assert mul.get_in_var(1).value == 0.25

    graph = factory.new_graph()
    assert graph.add(osc) == 0
    assert graph.add(mul) == 1
    assert len(graph) == 2 and graph[1] is mul
    assert graph.init() == 0
    assert graph.perform() == 0
    src = osc.get_out_var(0).samples
    assert mul.get_out_var(0).samples == pytest.approx([0.25 * s for s in src])

    gain.value = 0.5
    assert graph.perform() == 0
    src = osc.get_out_var(0).samples
    assert mul.get_out_var(0).samples == pytest.approx([0.5 * s for s in src])


def test_wired_sources_outlive_their_handles(factory):
    osc = _oscils(factory, amp=1.0, freq=SR / 8)
    mul = factory.new_ugen("##mul.ak", "a", "ak")
    mul.set_input_var(0, osc.get_out_var(0))
    gain = factory.new_var(T.K)
    gain.value = 2.0
    mul.set_input_var(1, gain)
    graph = factory.new_graph()
    graph.add(osc)
    graph.add(mul)
    del osc, gain
    gc.collect()
    assert graph.init() == 0 and graph.perform() == 0
    assert max(mul.get_out_var(0).samples) == pytest.approx(2.0, rel=1e-3)


def test_set_input_var_type_check(factory):
    osc = _oscils(factory)
    mul = factory.new_ugen("##mul.ak", "a", "ak")
    with pytest.raises(TypeError):
        mul.set_input_var(0, factory.new_var(T.K))  # k into an a-rate input
    with pytest.raises(TypeError):
        mul.set_input_var(1, osc.get_out_var(0))  # a into a k-rate input
    mul.set_input_var(1, factory.new_var(T.I))  # i and k scalars mix


def test_strings(factory):
    cat = factory.new_ugen("strcat", "S", "SS")
    cat.set_string(0, "uni")
    cat.set_string(1, "t generator")
    assert cat.init() == 0
    assert cat.get_string(0) == "unit generator"
    s = factory.new_var(T.S)
    assert s.string == ""
    s.string = "x" * 1000  # grows the STRINGDAT buffer
    assert s.string == "x" * 1000
    with pytest.raises(TypeError):
        cat.set_value(0, 1.0)  # a scalar write would clobber the STRINGDAT


def test_context(factory):
    # An opcode init error crashes the process (see Ugen), so this uses an
    # opcode that cannot fail rather than one that reads the release state.
    u = _oscils(factory)
    ctx = factory.new_context()
    u.set_context(ctx)
    del ctx
    gc.collect()  # the Ugen keeps the context alive
    assert u.init() == 0
    assert u.perform() == 0
    del u
    gc.collect()  # deinit and delete run while the context is still alive


def test_stale_after_reset(csound, factory):
    u = _oscils(factory)
    v = u.get_out_var(0)
    s = factory.new_var(T.K)
    csound.reset()
    for call in (u.init, factory.list_opcodes, lambda: v.samples,
                 lambda: s.value, factory.new_graph):
        with pytest.raises(ValueError):
            call()
    assert repr(v) == "<UgenVar stale>"
    del u, v, s, factory
    gc.collect()  # dealloc must not free pool memory reset() already freed


def test_cross_instance_rejected(factory):
    other = cycsound.Csound()
    for opt in ("-n", "-d", "-m0", f"--ksmps={KSMPS}"):
        other.set_option(opt)
    other.compile_orc("instr 1\nendin\n")
    other.start()
    f2 = other.ugen_factory()
    mul = factory.new_ugen("##mul.ak", "a", "ak")
    with pytest.raises(ValueError):
        mul.set_input_var(1, f2.new_var(T.K))
    with pytest.raises(ValueError):
        factory.new_graph().add(f2.new_ugen("oscils", "a", "iiio"))


def test_feedback_cycle_is_collected(factory):
    # Self-wiring makes a reference cycle; the GC clears it, and the Ugen
    # leaves its memory to the pool rather than freeing it out of order.
    add = factory.new_ugen("##add.aa", "a", "aa")
    add.set_input_var(0, add.get_out_var(0))
    add.set_input_var(1, add.get_out_var(0))
    assert add.init() == 0 and add.perform() == 0
    del add
    gc.collect()


def test_direct_index_helpers_match_var_route(factory):
    osc = factory.new_ugen("oscils", "a", "iiio")
    osc.set_in_value(1, 440.0)
    assert osc.get_in_var(1).value == 440.0
    line = factory.new_ugen("line", "k", "iii")
    for i, v in enumerate((2.0, 1.0, 3.0)):
        line.set_in_value(i, v)
    assert line.init() == 0 and line.perform() == 0
    assert line.get_out_value(0) == line.get_value(0) == 2.0

    cat = factory.new_ugen("strcat", "S", "SS")
    cat.set_in_string(0, "a")
    cat.set_in_string(1, "b")
    assert cat.init() == 0
    assert cat.get_out_string(0) == cat.get_string(0) == "ab"


def test_direct_index_helpers_guard_like_var_route(factory):
    osc = factory.new_ugen("oscils", "a", "iiio")
    cat = factory.new_ugen("strcat", "S", "SS")
    with pytest.raises(TypeError):
        cat.set_in_value(0, 1.0)  # csoundUgenSetValue would clobber the STRINGDAT
    with pytest.raises(TypeError):
        osc.get_out_value(0)  # csoundUgenGetValue would return sample 0 only
    with pytest.raises(TypeError):
        osc.set_in_string(0, "x")
    with pytest.raises(TypeError):
        osc.get_out_string(0)
    with pytest.raises(IndexError):
        osc.set_in_value(4, 1.0)  # Csound ignores a bad index silently
    with pytest.raises(IndexError):
        cat.get_out_string(1)


def _osc_mul_graph(factory):
    osc = _oscils(factory, amp=1.0, freq=SR / 8)
    mul = factory.new_ugen("##mul.ak", "a", "ak")
    mul.set_input_var(0, osc.get_out_var(0))
    mul.set_input_var(1, factory.new_var(T.K))
    graph = factory.new_graph()
    graph.add(osc)
    graph.add(mul)
    return osc, mul, graph


def test_delete_all_invalidates_graph_ugens_and_vars(factory):
    osc, mul, graph = _osc_mul_graph(factory)
    out = mul.get_out_var(0)
    gain = factory.new_var(T.K)  # standalone: not owned by the graph
    assert graph.init() == 0 and graph.perform() == 0
    graph.delete_all()
    for call in (graph.perform, lambda: graph.add(osc), osc.init, mul.perform,
                 lambda: out.samples, lambda: mul.get_out_var(0)):
        with pytest.raises(ValueError):
            call()
    assert len(graph) == 0
    gain.value = 1.0  # unaffected
    del osc, mul, out, graph
    gc.collect()  # deallocs must not delete the Ugens a second time


def test_delete_all_refuses_outside_reader(factory):
    osc, mul, graph = _osc_mul_graph(factory)
    reader = factory.new_ugen("##mul.ak", "a", "ak")
    reader.set_input_var(0, mul.get_out_var(0))
    with pytest.raises(ValueError, match="reads"):
        graph.delete_all()
    assert graph.perform() == 0  # nothing was deleted
    reader.set_input_var(0, factory.new_var(T.A))  # rewired: no longer reads mul
    graph.delete_all()
    assert reader.init() == 0


def test_delete_all_refuses_shared_or_repeated_ugen(factory):
    osc, mul, graph = _osc_mul_graph(factory)
    other = factory.new_graph()
    other.add(osc)
    with pytest.raises(ValueError, match="another graph"):
        graph.delete_all()
    with pytest.raises(ValueError, match="another graph"):
        other.delete_all()  # the check is symmetric
    assert graph.perform() == 0 and other.perform() == 0
    twice = factory.new_graph()
    u = _oscils(factory)
    twice.add(u)
    twice.add(u)
    with pytest.raises(ValueError, match="twice"):
        twice.delete_all()


def test_ugen_delete(factory):
    osc = _oscils(factory, amp=1.0, freq=SR / 8)
    out = osc.get_out_var(0)
    mul = factory.new_ugen("##mul.ak", "a", "ak")
    mul.set_input_var(0, out)
    with pytest.raises(ValueError, match="reads"):
        osc.delete()  # mul would read freed memory
    graph = factory.new_graph()
    graph.add(mul)
    with pytest.raises(ValueError, match="in a graph"):
        mul.delete()  # the graph holds mul's pointer
    graph.delete_all()  # mul only; osc stays
    assert osc.init() == 0 and osc.perform() == 0
    osc.delete()
    for call in (osc.init, osc.delete, lambda: out.samples):
        with pytest.raises(ValueError, match="deleted"):
            call()
    del osc, out
    gc.collect()  # dealloc must not delete osc a second time


def test_ugen_delete_with_feedback(factory):
    add = factory.new_ugen("##add.aa", "a", "aa")
    add.set_input_var(0, add.get_out_var(0))  # reads itself: no outside reader
    add.delete()
    with pytest.raises(ValueError):
        add.perform()
