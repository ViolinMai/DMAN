from backend.alldebrid_api import AllDebridClient, AllDebridError

c = AllDebridClient("KAF4QMTCJ9L6Z2G8F223")
LINK = "رابط حقيقي من host مدعوم"

for name, fn in [("user", lambda: c.get_user_info(force_refresh=True)),
                 ("domains", lambda: len(c.get_supported_domains())),
                 ("unlock", lambda: c.unlock_link(LINK))]:
    try:
        print(name, "OK:", fn())
    except AllDebridError as e:
        print(name, "AllDebridError code =", e.code, "| msg =", e.message)
    except Exception as e:
        print(name, "OTHER:", repr(e))
