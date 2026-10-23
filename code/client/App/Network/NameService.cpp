#include "NameService.h"

#include "Session.h"

#include <cctype>
#include <thread>
#include <windows.h>
#include <winhttp.h>

#pragma comment(lib, "winhttp.lib")

struct NameService::State
{
    mutable std::mutex Lock;
    uint64_t LatestRequest = 0;
    Status Current = Status::Idle;
    std::string Message;
    std::string StatusName;
    std::string CharacterName;
    std::string PendingName;
};

namespace
{
std::wstring Widen(const std::string& aText)
{
    if (aText.empty())
        return {};
    const int size = MultiByteToWideChar(CP_UTF8, 0, aText.data(), static_cast<int>(aText.size()), nullptr, 0);
    std::wstring out(size, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, aText.data(), static_cast<int>(aText.size()), out.data(), size);
    return out;
}

std::string UrlEncode(const std::string& aText)
{
    static constexpr char kHex[] = "0123456789ABCDEF";
    std::string out;
    for (const unsigned char c : aText)
    {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~')
            out += static_cast<char>(c);
        else
        {
            out += '%';
            out += kHex[c >> 4];
            out += kHex[c & 15];
        }
    }
    return out;
}

struct HttpResult
{
    DWORD StatusCode = 0;
    std::string Body;
    bool Ok = false; // the request completed (any HTTP status)
};

struct HandleCloser
{
    void operator()(HINTERNET aHandle) const
    {
        if (aHandle)
            WinHttpCloseHandle(aHandle);
    }
};
using Handle = std::unique_ptr<void, HandleCloser>;

// Small blocking HTTP call; only ever run on a worker thread.
HttpResult Http(const wchar_t* aMethod, const std::string& aUrl, const std::string& aBearer, const std::string& aBody)
{
    HttpResult result;
    const auto url = Widen(aUrl);

    wchar_t host[256]{};
    wchar_t path[2048]{};
    wchar_t extra[2048]{};
    URL_COMPONENTS parts{};
    parts.dwStructSize = sizeof(parts);
    parts.lpszHostName = host;
    parts.dwHostNameLength = static_cast<DWORD>(std::size(host));
    parts.lpszUrlPath = path;
    parts.dwUrlPathLength = static_cast<DWORD>(std::size(path));
    parts.lpszExtraInfo = extra;
    parts.dwExtraInfoLength = static_cast<DWORD>(std::size(extra));
    if (!WinHttpCrackUrl(url.c_str(), 0, 0, &parts))
        return result;

    const Handle session(WinHttpOpen(L"CyberpunkMP", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
    if (!session)
        return result;
    WinHttpSetTimeouts(session.get(), 5000, 5000, 10000, 10000);

    const Handle connection(WinHttpConnect(session.get(), host, parts.nPort, 0));
    if (!connection)
        return result;

    const std::wstring target = std::wstring(path) + extra;
    const DWORD flags = parts.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0;
    const Handle request(WinHttpOpenRequest(connection.get(), aMethod, target.c_str(), nullptr, WINHTTP_NO_REFERER,
                                            WINHTTP_DEFAULT_ACCEPT_TYPES, flags));
    if (!request)
        return result;

    std::wstring headers = L"Content-Type: application/json\r\nAuthorization: Bearer " + Widen(aBearer) + L"\r\n";
    if (!WinHttpSendRequest(request.get(), headers.c_str(), static_cast<DWORD>(-1),
                            aBody.empty() ? WINHTTP_NO_REQUEST_DATA : const_cast<char*>(aBody.data()),
                            static_cast<DWORD>(aBody.size()), static_cast<DWORD>(aBody.size()), 0))
        return result;

    if (!WinHttpReceiveResponse(request.get(), nullptr))
        return result;

    DWORD statusSize = sizeof(result.StatusCode);
    WinHttpQueryHeaders(request.get(), WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX,
                        &result.StatusCode, &statusSize, WINHTTP_NO_HEADER_INDEX);

    DWORD available = 0;
    while (WinHttpQueryDataAvailable(request.get(), &available) && available > 0)
    {
        std::string chunk(available, '\0');
        DWORD read = 0;
        if (!WinHttpReadData(request.get(), chunk.data(), available, &read) || read == 0)
            break;
        chunk.resize(read);
        result.Body += chunk;
        if (result.Body.size() > 64 * 1024) // answers here are tiny; don't read anything huge
            break;
    }

    result.Ok = true;
    return result;
}
} // namespace

NameService& NameService::Get()
{
    static NameService s_instance;
    return s_instance;
}

NameService::NameService()
    : m_state(std::make_shared<State>())
{
}

bool NameService::HasSession() const
{
    const auto session = Session::Read();
    return session && !session->ApiUrl.empty();
}

void NameService::RequestCheck(const std::string& aName)
{
    Start(aName, false);
}

void NameService::RequestReserve(const std::string& aName)
{
    Start(aName, true);
}

void NameService::Start(const std::string& aName, bool aReserve)
{
    uint64_t id;
    {
        std::scoped_lock lock(m_state->Lock);
        id = ++m_state->LatestRequest;
        m_state->Current = aReserve ? Status::Reserving : Status::Checking;
        m_state->Message = aReserve ? "Reserving..." : "Checking...";
        m_state->StatusName = aName;
    }

    // The worker only touches the shared state, so it's safe even if the game
    // moves on (or quits) before the answer arrives. Older answers are ignored.
    std::thread([state = m_state, id, aName, aReserve]() {
        auto finish = [&](Status aStatus, const std::string& aMessage) {
            std::scoped_lock lock(state->Lock);
            if (state->LatestRequest != id)
                return;
            state->Current = aStatus;
            state->Message = aMessage;
        };

        const auto session = Session::Read();
        if (!session || session->ApiUrl.empty())
            return finish(Status::Error, "Start the game from the server launcher to create a character.");

        const auto base = session->ApiUrl + "/api/v1/plugins/account";
        const auto result = aReserve
            ? Http(L"POST", base + "/characters", session->SessionToken, nlohmann::json{{"name", aName}}.dump())
            : Http(L"GET", base + "/name-check?name=" + UrlEncode(aName), session->SessionToken, {});

        if (!result.Ok || result.StatusCode != 200)
            return finish(Status::Error, "Couldn't reach the server. Check your connection and try again.");

        try
        {
            const auto json = nlohmann::json::parse(result.Body);
            const bool ok = json.value("Ok", json.value("ok", false));
            const auto message = json.value("Message", json.value("message", std::string{}));

            if (aReserve)
                finish(ok ? Status::Reserved : Status::Unavailable, message);
            else
                finish(ok ? Status::Available : Status::Unavailable, message);
        }
        catch (const std::exception&)
        {
            finish(Status::Error, "The server sent an answer the game couldn't read.");
        }
    }).detach();
}

NameService::Status NameService::GetStatus() const
{
    std::scoped_lock lock(m_state->Lock);
    return m_state->Current;
}

std::string NameService::GetStatusMessage() const
{
    std::scoped_lock lock(m_state->Lock);
    return m_state->Message;
}

std::string NameService::GetStatusName() const
{
    std::scoped_lock lock(m_state->Lock);
    return m_state->StatusName;
}

void NameService::SetCharacterName(const std::string& aName)
{
    std::scoped_lock lock(m_state->Lock);
    m_state->CharacterName = aName;
}

std::string NameService::GetCharacterName() const
{
    std::scoped_lock lock(m_state->Lock);
    return m_state->CharacterName;
}

void NameService::SetPendingName(const std::string& aName)
{
    std::scoped_lock lock(m_state->Lock);
    m_state->PendingName = aName;
}

std::string NameService::TakePendingName()
{
    std::scoped_lock lock(m_state->Lock);
    return std::exchange(m_state->PendingName, std::string{});
}
