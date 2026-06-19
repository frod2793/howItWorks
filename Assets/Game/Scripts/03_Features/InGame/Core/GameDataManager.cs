using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.Networking;
using Cysharp.Threading.Tasks;
using Domain.InGame;

namespace Features.InGame
{
    public class GameDataManager : IGameDataManager
    {
        private SaveDataFileDTO m_saveData;
        private List<CharacterDTO> m_characters;
        private List<SceneDTO> m_scenes;
        private List<BranchDTO> m_branches;
        private List<ActOptionDTO> m_actMenu;
        private List<InventoryItemDTO> m_inventory;
        private List<GameModuleDTO> m_modules;
        private List<DialogueLineDTO> m_dialogueLog;
        private GameSettingsDTO m_settings;
        private List<AchievementDTO> m_achievements;
        private List<EmotionTrendRowDTO> m_emotionTrends;
        private List<PlaythroughLogRowDTO> m_playthroughLogs;
        private List<BranchMatrixDTO> m_branchMatrix;
        private List<SubplotDTO> m_subplots;
        private List<LoopVariationDTO> m_loopVariations;
        private List<ChoiceTriggerDTO> m_choiceTriggers;

        public async UniTask LoadAllDataAsync()
        {
            m_saveData = await LoadJsonAsync<SaveDataFileDTO>("save_data.json");
            m_characters = await LoadJsonListAsync<CharacterDTO>("characters.json");
            m_scenes = await LoadJsonListAsync<SceneDTO>("scenes.json");
            m_branches = await LoadJsonListAsync<BranchDTO>("branches.json");
            m_actMenu = await LoadJsonListAsync<ActOptionDTO>("act_menu.json");
            m_inventory = await LoadJsonListAsync<InventoryItemDTO>("inventory.json");
            m_modules = await LoadJsonListAsync<GameModuleDTO>("modules.json");
            m_dialogueLog = await LoadJsonListAsync<DialogueLineDTO>("dialogue_log.json");
            m_settings = await LoadJsonAsync<GameSettingsDTO>("settings.json");
            m_achievements = await LoadJsonListAsync<AchievementDTO>("achievements.json");
            m_branchMatrix = await LoadJsonListAsync<BranchMatrixDTO>("branch_matrix.json");
            m_subplots = await LoadJsonListAsync<SubplotDTO>("subplots.json");
            m_loopVariations = await LoadJsonListAsync<LoopVariationDTO>("loop_variations.json");
            m_choiceTriggers = await LoadJsonListAsync<ChoiceTriggerDTO>("choices_data.json");

            await LoadEmotionTrendsAsync();
            await LoadPlaythroughLogsAsync();
        }

        private async UniTask<T> LoadJsonAsync<T>(string fileName)
        {
            string jsonText = await ReadFileTextAsync(fileName);
            if (string.IsNullOrEmpty(jsonText))
            {
                return default;
            }
            return JsonUtility.FromJson<T>(jsonText);
        }

        private async UniTask<List<T>> LoadJsonListAsync<T>(string fileName)
        {
            string jsonText = await ReadFileTextAsync(fileName);
            if (string.IsNullOrEmpty(jsonText))
            {
                return new List<T>();
            }
            string wrappedJson = $"{{\"items\":{jsonText}}}";
            Wrapper<T> wrapper = JsonUtility.FromJson<Wrapper<T>>(wrappedJson);
            if (wrapper != null && wrapper.items != null)
            {
                return wrapper.items;
            }
            return new List<T>();
        }

        private async UniTask LoadEmotionTrendsAsync()
        {
            m_emotionTrends = new List<EmotionTrendRowDTO>();
            string csvText = await ReadFileTextAsync("emotion_trend.csv");
            if (string.IsNullOrEmpty(csvText))
            {
                return;
            }

            List<string[]> parsed = CSVParser.Parse(csvText);
            for (int i = 1; i < parsed.Count; i++)
            {
                string[] row = parsed[i];
                if (row.Length >= 6)
                {
                    m_emotionTrends.Add(new EmotionTrendRowDTO
                    {
                        playthrough = int.Parse(row[0]),
                        joy = int.Parse(row[1]),
                        fear = int.Parse(row[2]),
                        monitoring = int.Parse(row[3]),
                        trust = int.Parse(row[4]),
                        surprise = int.Parse(row[5])
                    });
                }
            }
        }

        private async UniTask LoadPlaythroughLogsAsync()
        {
            m_playthroughLogs = new List<PlaythroughLogRowDTO>();
            string csvText = await ReadFileTextAsync("playthrough_log.csv");
            if (string.IsNullOrEmpty(csvText))
            {
                return;
            }

            List<string[]> parsed = CSVParser.Parse(csvText);
            for (int i = 1; i < parsed.Count; i++)
            {
                string[] row = parsed[i];
                if (row.Length >= 4)
                {
                    m_playthroughLogs.Add(new PlaythroughLogRowDTO
                    {
                        playthrough = int.Parse(row[0]),
                        playTimeSeconds = int.Parse(row[1]),
                        endingId = row[2],
                        branchesPassed = new List<string>(row[3].Split(';'))
                    });
                }
            }
        }

        private async UniTask<string> ReadFileTextAsync(string fileName)
        {
            string path = Path.Combine(Application.streamingAssetsPath, "Data", fileName);
            if (path.Contains("://") || path.Contains(":///"))
            {
                using var webRequest = UnityWebRequest.Get(path);
                await webRequest.SendWebRequest();
                if (webRequest.result == UnityWebRequest.Result.Success)
                {
                    return webRequest.downloadHandler.text;
                }
                return string.Empty;
            }

            if (!File.Exists(path))
            {
                return string.Empty;
            }

            using var reader = new StreamReader(path);
            return await reader.ReadToEndAsync();
        }

        [Serializable]
        private class Wrapper<T>
        {
            public List<T> items;
        }

        public SaveDataFileDTO GetSaveData() { return m_saveData; }
        public List<CharacterDTO> GetCharacters() { return m_characters; }
        public List<SceneDTO> GetScenes() { return m_scenes; }
        public List<BranchDTO> GetBranches() { return m_branches; }
        public List<ActOptionDTO> GetActMenu() { return m_actMenu; }
        public List<InventoryItemDTO> GetInventory() { return m_inventory; }
        public List<GameModuleDTO> GetModules() { return m_modules; }
        public List<DialogueLineDTO> GetDialogueLog() { return m_dialogueLog; }
        public GameSettingsDTO GetSettings() { return m_settings; }
        public List<AchievementDTO> GetAchievements() { return m_achievements; }
        public List<EmotionTrendRowDTO> GetEmotionTrends() { return m_emotionTrends; }
        public List<PlaythroughLogRowDTO> GetPlaythroughLogs() { return m_playthroughLogs; }
        public List<BranchMatrixDTO> GetBranchMatrix() { return m_branchMatrix; }
        public List<SubplotDTO> GetSubplots() { return m_subplots; }
        public List<LoopVariationDTO> GetLoopVariations() { return m_loopVariations; }
        public List<ChoiceTriggerDTO> GetChoiceTriggers() { return m_choiceTriggers; }
    }
}
