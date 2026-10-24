class_name EditCheck
extends RefCounted
## One read-only proposal check. Warnings describe the resulting shop and do
## not change ok. Existing item ids are positive; 0 denotes a proposed new buy.

var ok: bool = false
var why: String = ""
var unreachable: Array[int] = []


func _init(allowed: bool = false, reason: String = "") -> void:
	ok = allowed
	why = reason
