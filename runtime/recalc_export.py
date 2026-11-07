# -*- coding: utf-8 -*-
# Ouvre un xlsx dans LibreOffice, recalcule, ecrit B5, exporte en PDF.
# Arguments : xlsx pdf port resultat.txt
import sys
import time

import uno
from com.sun.star.beans import PropertyValue


def prop(name, value):
    item = PropertyValue()
    item.Name = name
    item.Value = value
    return item


def main():
    if len(sys.argv) != 5:
        sys.stderr.write("usage: recalc_export.py xlsx pdf port resultat.txt\n")
        return 2
    src, dst, port, result_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    local = uno.getComponentContext()
    resolver = local.ServiceManager.createInstanceWithContext(
        "com.sun.star.bridge.UnoUrlResolver", local)
    ctx = None
    last = None
    url = "uno:socket,host=127.0.0.1,port=%s;urp;StarOffice.ComponentContext" % port
    for _ in range(40):
        try:
            ctx = resolver.resolve(url)
            break
        except Exception as ex:
            last = ex
            time.sleep(0.5)
    if ctx is None:
        sys.stderr.write("UNO indisponible: %s\n" % last)
        return 3
    desktop = ctx.ServiceManager.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)
    doc = desktop.loadComponentFromURL(
        uno.systemPathToFileUrl(src),
        "_blank",
        0,
        (prop("Hidden", True), prop("UpdateDocMode", 3)))
    if doc is None:
        sys.stderr.write("Ouverture impossible\n")
        return 4
    try:
        doc.calculateAll()
        sheet = doc.getSheets().getByName("Fiche Inventaire")
        cell = sheet.getCellByPosition(1, 4)
        err = 0
        try:
            err = int(cell.getError())
        except Exception:
            err = 0
        if err:
            text = "#ERR:%s" % err
        else:
            text = cell.getString()
        text = (text or "").replace("\r", " ").replace("\n", " ").strip()
        handle = open(result_path, "wb")
        try:
            if not isinstance(text, bytes):
                text = text.encode("utf-8")
            handle.write(text)
        finally:
            handle.close()
        doc.storeToURL(
            uno.systemPathToFileUrl(dst),
            (prop("FilterName", "calc_pdf_Export"),))
    finally:
        doc.close(True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
