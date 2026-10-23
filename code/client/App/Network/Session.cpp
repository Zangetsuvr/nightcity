#include "Session.h"

#include <fstream>

extern std::filesystem::path GCyberpunkMpLocation;

std::optional<Session> Session::Read()
{
    try
    {
        std::ifstream file(GCyberpunkMpLocation / "session.json");
        if (!file)
            return std::nullopt;

        const auto json = nlohmann::json::parse(file);

        Session session;
        session.ApiUrl = json.value("apiUrl", std::string{});
        session.Token = json.value("token", std::string{});
        session.SessionToken = session.Token.substr(0, session.Token.find(':'));
        if (json.contains("characters") && json["characters"].is_array())
        {
            for (const auto& name : json["characters"])
                if (name.is_string())
                    session.Characters.push_back(name.get<std::string>());
        }

        while (!session.ApiUrl.empty() && session.ApiUrl.back() == '/')
            session.ApiUrl.pop_back();

        if (session.Token.empty())
            return std::nullopt;
        return session;
    }
    catch (const std::exception& e)
    {
        spdlog::error("Could not read session.json: {}", e.what());
        return std::nullopt;
    }
}
