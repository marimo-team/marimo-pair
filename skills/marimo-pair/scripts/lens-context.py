"""Execute one marimo Lens action in the active notebook kernel."""

import base64 as _base64
import json as _json
import re as _re
import secrets as _secrets
import sys as _sys
import types as _types
import weakref as _weakref
from collections.abc import Mapping as _Mapping

_MAX_ALIASES = 4
_MAX_AMBIGUOUS_LENSES = 8
_MAX_CURRENT_NOTE = 1_000
_MAX_DOM_TEXT = 240
_MAX_GRAPH_NAME = 80
_MAX_GRAPH_NAMES = 16
_MAX_IDENTIFIER = 128
_MAX_INDEXED_SELECTIONS = 16
_MAX_NOTE_PREVIEW = 80
_MAX_NOTEBOOK_PATH = 900
_MAX_REASON = 240
_TOKEN_MODULE = "_marimo_pair_lens_tokens"
_MANGLED_BINDING = _re.compile(r"^_cell_(?:[^\W_][\w-]*?)(_.*)$")

_CONFIG = _json.loads(_MARIMO_LENS_CONFIG_JSON)  # noqa: F821
_ACTION = str(_CONFIG.get("action") or "")
_ARGS = _CONFIG.get("args") if isinstance(_CONFIG.get("args"), _Mapping) else {}
_MARKER = str(_CONFIG.get("marker") or "")


def _bounded(_value, _maximum):
    _text = str(_value or "")
    return _text[:_maximum], len(_text) > _maximum


def _identifier(_value):
    return _bounded(_value, _MAX_IDENTIFIER)[0]


def _binding_name(_value):
    _name = str(_value)
    _match = _MANGLED_BINDING.match(_name)
    return _name if _match is None else _match.group(1)


def _ordered_names(_values):
    return sorted(set(_values), key=lambda _name: (_name.startswith("_"), _name))


def _find_lenses(_globals, _lens_type):
    _by_widget = {}
    for _name, _value in _globals.items():
        if isinstance(_value, _lens_type):
            _widget = _value
        elif type(_value).__module__.startswith("marimo."):
            _widget = getattr(_value, "widget", None)
        else:
            continue
        if not isinstance(_widget, _lens_type):
            continue
        if hasattr(_widget, "comm") and _widget.comm is None:
            continue
        _entry = _by_widget.setdefault(id(_widget), {"widget": _widget, "names": set()})
        _entry["names"].add(_binding_name(_name))
    return list(_by_widget.values())


def _token_registry():
    _module = _sys.modules.get(_TOKEN_MODULE)
    if _module is None:
        _module = _types.ModuleType(_TOKEN_MODULE)
        _module.entries = {}
        _sys.modules[_TOKEN_MODULE] = _module
    _entries = _module.entries
    for _token, _reference in list(_entries.items()):
        if _reference() is None:
            _entries.pop(_token, None)
    return _entries


def _lens_token(_widget):
    _entries = _token_registry()
    for _token, _reference in _entries.items():
        if _reference() is _widget:
            return _token
    _token = _secrets.token_urlsafe(24)
    _entries[_token] = _weakref.ref(
        _widget,
        lambda _reference, _token=_token: _entries.pop(_token, None),
    )
    return _token


def _preview(_value, _maximum=_MAX_NOTE_PREVIEW):
    _text, _truncated = _bounded(_value, _maximum)
    return {"text": _text, "truncated": _truncated}


def _selection_index(_selection, _current_id):
    _anchor = _selection.get("anchor")
    _snapshot = _selection.get("snapshot")
    return {
        "id": _identifier(_selection.get("id")),
        "label": _identifier(_selection.get("label")),
        "current": _selection.get("id") == _current_id,
        "outputCellId": _identifier(_selection.get("outputCellId")),
        "cellStatus": _identifier(_selection.get("cellStatus")),
        "anchorKind": _anchor.get("kind") if isinstance(_anchor, _Mapping) else None,
        "notePreview": _preview(_selection.get("note")),
        "snapshotStatus": (
            _snapshot.get("status") if isinstance(_snapshot, _Mapping) else None
        ),
    }


def _current_selection(_selection):
    if not isinstance(_selection, _Mapping):
        return None
    _snapshot = _selection.get("snapshot")
    _result = {
        "id": _identifier(_selection.get("id")),
        "label": _identifier(_selection.get("label")),
        "outputCellId": _identifier(_selection.get("outputCellId")),
        "cellStatus": _identifier(_selection.get("cellStatus")),
        "anchor": _selection.get("anchor"),
        "note": _preview(_selection.get("note"), _MAX_CURRENT_NOTE),
        "snapshotStatus": (
            _snapshot.get("status") if isinstance(_snapshot, _Mapping) else None
        ),
    }
    _dom_hint = _selection.get("domHint")
    if isinstance(_dom_hint, _Mapping):
        _dom = {}
        _truncated = False
        for _field, _maximum in (
            ("tag", 40),
            ("role", 80),
            ("ariaLabel", 160),
            ("title", 160),
            ("text", _MAX_DOM_TEXT),
        ):
            _text, _field_truncated = _bounded(_dom_hint.get(_field), _maximum)
            if _text:
                _dom[_field] = _text
            _truncated = _truncated or _field_truncated
        if _dom:
            _result["domHint"] = _dom
        if _truncated:
            _result["domHintTruncated"] = True
    _previous = _selection.get("previousResolution")
    if isinstance(_previous, _Mapping):
        _addressed_at, _ = _bounded(_previous.get("addressedAt"), 80)
        if _addressed_at:
            _receipt = {"addressedAt": _addressed_at}
            _summary, _ = _bounded(_previous.get("summary"), 240)
            if _summary:
                _receipt["summary"] = _summary
            _result["previousResolution"] = _receipt
    return _result


def _graph_names(_values):
    _all = sorted(str(_value) for _value in _values)
    _included = [
        _bounded(_value, _MAX_GRAPH_NAME)[0] for _value in _all[:_MAX_GRAPH_NAMES]
    ]
    return _included, max(0, len(_all) - len(_included))


def _cell_summary(_ctx, _cell_id):
    if not isinstance(_cell_id, str):
        return None
    _cell = _ctx.graph.cells.get(_cell_id)
    if _cell is None:
        return {"id": _identifier(_cell_id), "status": "missing"}
    _defs, _omitted_defs = _graph_names(_cell.defs)
    _refs, _omitted_refs = _graph_names(_cell.refs)
    _result = {
        "id": _identifier(_cell_id),
        "status": "available",
        "defs": _defs,
        "refs": _refs,
        "codeCharacters": len(str(_cell.code or "")),
    }
    if _omitted_defs:
        _result["omittedDefCount"] = _omitted_defs
    if _omitted_refs:
        _result["omittedRefCount"] = _omitted_refs
    return _result


def _notebook_summary(_value):
    if not isinstance(_value, _Mapping):
        return None
    _path, _path_truncated = _bounded(_value.get("path"), _MAX_NOTEBOOK_PATH)
    _result = {"path": _path, "available": _value.get("available") is True}
    if _path_truncated:
        _result["pathTruncated"] = True
    if _value.get("available") is False:
        _reason, _reason_truncated = _bounded(_value.get("reason"), _MAX_REASON)
        _result["reason"] = _reason
        if _reason_truncated:
            _result["reasonTruncated"] = True
    return _result


def _selection_rows(_references):
    _values = _references.get("selections")
    if not isinstance(_values, list):
        return []
    return [dict(_value) for _value in _values if isinstance(_value, _Mapping)]


def _scan(_ctx, _candidate, _context, _token):
    _references = _context.references
    _selections = _selection_rows(_references)
    _current_id = _references.get("currentSelectionId")
    _current = next(
        (
            _selection
            for _selection in _selections
            if _selection.get("id") == _current_id
        ),
        None,
    )
    _ordered = ([] if _current is None else [_current]) + [
        _selection for _selection in _selections if _selection.get("id") != _current_id
    ]
    _indexed = _ordered[:_MAX_INDEXED_SELECTIONS]
    _names = _ordered_names(_candidate["names"])
    return {
        "status": "ready",
        "lensToken": _token,
        "revision": _context.revision,
        "lens": {
            "variable": _identifier(_names[0]),
            "aliases": [_identifier(_name) for _name in _names[1 : _MAX_ALIASES + 1]],
            "omittedAliasCount": max(0, len(_names) - _MAX_ALIASES - 1),
        },
        "notebook": _notebook_summary(_references.get("notebook")),
        "selectionCount": len(_selections),
        "omittedSelectionCount": max(0, len(_selections) - len(_indexed)),
        "current": _current_selection(_current),
        "selections": [
            _selection_index(_selection, _current_id) for _selection in _indexed
        ],
        "currentCell": _cell_summary(
            _ctx,
            None if _current is None else _current.get("outputCellId"),
        ),
    }


def _revision_conflict(_context, _expected_revision):
    if _context.revision == _expected_revision:
        return None
    return {
        "status": "revision-conflict",
        "expectedRevision": _expected_revision,
        "revision": _context.revision,
    }


def _find_selection(_context, _selection_id):
    _selection = next(
        (
            _candidate
            for _candidate in _selection_rows(_context.references)
            if _candidate.get("id") == _selection_id
        ),
        None,
    )
    if _selection is None:
        return None, {
            "status": "selection-not-found",
            "selectionId": _identifier(_selection_id),
            "revision": _context.revision,
        }
    return _selection, None


def _find_selections(_context, _selection_ids):
    if not isinstance(_selection_ids, list) or not _selection_ids:
        return None, {
            "status": "error",
            "code": "invalid_selection",
            "error": "Pair must supply at least one selection ID.",
        }
    if (
        len(_selection_ids) > 64
        or any(not isinstance(_selection_id, str) for _selection_id in _selection_ids)
        or len(_selection_ids) != len(set(_selection_ids))
    ):
        return None, {
            "status": "error",
            "code": "invalid_selection",
            "error": "Pair must supply 1 through 64 unique selection IDs.",
        }
    _selections = []
    for _selection_id in _selection_ids:
        _selection, _error = _find_selection(_context, _selection_id)
        if _error is not None:
            return None, _error
        _selections.append(_selection)
    return _selections, None


def _selection_image(_context, _args):
    _conflict = _revision_conflict(_context, _args.get("revision"))
    if _conflict is not None:
        return _conflict
    _selection, _error = _find_selection(_context, _args.get("selectionId"))
    if _error is not None:
        return _error
    _image = next(
        (
            _candidate
            for _candidate in _context.images
            if _candidate.selection_id == _selection.get("id")
        ),
        None,
    )
    if _image is None:
        return {
            "status": "image-unavailable",
            "selection": _identifier(_selection.get("label")),
            "selectionId": _identifier(_selection.get("id")),
            "revision": _context.revision,
        }
    return {
        "status": "ready",
        "source": "selection",
        "selection": _identifier(_selection.get("label")),
        "selectionId": _identifier(_selection.get("id")),
        "revision": _context.revision,
        "cellId": _identifier(_selection.get("outputCellId")),
        "mediaType": _image.media_type,
        "bytes": len(_image.data),
        "width": _image.width,
        "height": _image.height,
        "sha256": _image.sha256,
        "capturedAt": _image.captured_at,
        "outdated": _image.outdated,
        "data": _base64.b64encode(_image.data).decode("ascii"),
    }


def _read_output_capture(_widget, _request_id):
    _capture = _widget._read_output_capture(_request_id)
    _result = {
        "status": str(_capture.status),
        "requestId": str(_capture.request_id),
        "cellId": str(_capture.cell_id),
        "selectionCount": len(_capture.selection_ids),
    }
    if _capture.status == "pending":
        return _result
    if _capture.status == "failed":
        return {
            **_result,
            "errorCode": _identifier(_capture.error_code or "capture_failed"),
            "error": _bounded(_capture.error or "Cell output capture failed.", 500)[0],
        }
    _image = _capture.image
    if (
        _capture.status != "available"
        or _image is None
        or getattr(_image, "request_id", None) != _capture.request_id
        or getattr(_image, "cell_id", None) != _capture.cell_id
    ):
        return {
            **_result,
            "status": "error",
            "code": "invalid_capture",
            "error": "Lens returned an invalid output capture result.",
        }
    return {
        **_result,
        "source": "cell",
        "mediaType": _image.media_type,
        "bytes": len(_image.data),
        "width": _image.width,
        "height": _image.height,
        "sha256": _image.sha256,
        "capturedAt": _image.captured_at,
        "data": _base64.b64encode(_image.data).decode("ascii"),
    }


def _dispatch(_ctx, _widget, _candidate, _token):
    if _ACTION == "activity":
        _widget.activity(
            _ARGS.get("cellId"),
            label=_ARGS.get("label"),
            message=_ARGS.get("message"),
        )
        return {"status": "activity-requested", "cellId": _ARGS.get("cellId")}
    if _ACTION == "reveal":
        _widget.reveal(_ARGS.get("cellId"), message=_ARGS.get("message"))
        return {"status": "reveal-requested", "cellId": _ARGS.get("cellId")}
    if _ACTION == "output.capture.read":
        return _read_output_capture(_widget, _ARGS.get("requestId"))

    _context = _widget.context()
    if _ACTION == "output.capture.start":
        _conflict = _revision_conflict(_context, _ARGS.get("revision"))
        if _conflict is not None:
            return _conflict
        _request_id = _widget._start_output_capture(_ARGS.get("cellId"))
        return {
            "status": "pending",
            "requestId": _request_id,
            "cellId": _ARGS.get("cellId"),
        }
    if _ACTION == "scan":
        return _scan(_ctx, _candidate, _context, _token)
    if _ACTION == "text":
        _conflict = _revision_conflict(_context, _ARGS.get("revision"))
        if _conflict is not None:
            return _conflict
        return {
            "status": "ready",
            "revision": _context.revision,
            "text": _context.text,
        }
    if _ACTION == "selection.image":
        return _selection_image(_context, _ARGS)
    if _ACTION == "resolve":
        _conflict = _revision_conflict(_context, _ARGS.get("revision"))
        if _conflict is not None:
            return _conflict
        _selections, _error = _find_selections(
            _context,
            _ARGS.get("selectionIds"),
        )
        if _error is not None:
            return _error
        _revision = _widget.resolve(
            [_selection["id"] for _selection in _selections],
            expected_revision=_context.revision,
            summary=_ARGS.get("summary"),
        )
        return {
            "status": "resolved",
            "selectionCount": len(_selections),
            "revision": _revision,
        }
    return {
        "status": "error",
        "code": "invalid_action",
        "error": "Pair requested an unknown Lens action.",
    }


def _identity_error(_token):
    if _ACTION not in {
        "text",
        "selection.image",
        "output.capture.start",
        "output.capture.read",
        "activity",
        "reveal",
        "resolve",
    }:
        return None
    _expected = _ARGS.get("lensToken")
    if not isinstance(_expected, str) or not _expected:
        return {
            "status": "error",
            "code": "lens_token_required",
            "error": "Pair must supply the Lens identity from its grounding scan.",
        }
    if _expected != _token:
        return {
            "status": "error",
            "code": "lens_changed",
            "error": "The Lens instance changed after the grounding scan.",
        }
    return None


def _lens_error(_error):
    _code = _identifier(getattr(_error, "code", None) or "lens_error")
    if _code == "selection_not_found":
        _selection_ids = _ARGS.get("selectionIds")
        _selection_id = (
            _selection_ids[0]
            if isinstance(_selection_ids, list) and _selection_ids
            else _ARGS.get("selectionId")
        )
        return {
            "status": "selection-not-found",
            "selectionId": _identifier(_selection_id),
            "revision": getattr(_error, "revision", None),
        }
    if _code == "revision_conflict":
        return {
            "status": "revision-conflict",
            "expectedRevision": _ARGS.get("revision"),
            "revision": getattr(_error, "revision", None),
        }
    return {
        "status": "error",
        "code": _code,
        "revision": getattr(_error, "revision", None),
        "error": _bounded(_error, 500)[0],
    }


async def _run():
    try:
        import marimo._code_mode as _cm
        from marimo_lens import Lens as _Lens
        from marimo_lens import LensError as _LensError
    except ModuleNotFoundError as _error:
        if _error.name == "marimo_lens":
            return {"status": "absent"}
        return {
            "status": "error",
            "code": "runtime_unavailable",
            "error": _bounded(f"{type(_error).__name__}: {_error}", 500)[0],
        }

    async with _cm.get_context() as _ctx:
        _candidates = _find_lenses(_ctx.globals, _Lens)
        if not _candidates:
            return {"status": "absent"}
        if len(_candidates) > 1:
            return {
                "status": "ambiguous",
                "lenses": [
                    _ordered_names(_candidate["names"])
                    for _candidate in _candidates[:_MAX_AMBIGUOUS_LENSES]
                ],
                "omittedLensCount": max(0, len(_candidates) - _MAX_AMBIGUOUS_LENSES),
            }
        _candidate = _candidates[0]
        _widget = _candidate["widget"]
        _token = _lens_token(_widget)
        _error = _identity_error(_token)
        if _error is not None:
            return _error
        try:
            return _dispatch(_ctx, _widget, _candidate, _token)
        except _LensError as _error:
            return _lens_error(_error)
        except Exception as _error:
            return {
                "status": "error",
                "code": "lens_error",
                "error": _bounded(f"{type(_error).__name__}: {_error}", 500)[0],
            }


_RESULT = await _run()  # noqa: F704
print(
    _MARKER
    + _json.dumps(
        {"action": _ACTION, "result": _RESULT},
        ensure_ascii=False,
        separators=(",", ":"),
    )
)
