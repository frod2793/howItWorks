using System;
using System.Collections.Generic;

namespace Domain.InGame
{
    [Serializable]
    public class PlayerStatsDTO
    {
        public int SceneNumber;
        public string CurrentLocation;
        public int Day;
        public int Playthrough;
        public int HP;
        public int MaxHP;
        public int Money;
    }

    [Serializable]
    public class SceneInfoDTO
    {
        public string ActName;
        public int SceneNumber;
        public string SceneTitle;
        public string Location;
        public string TimeOfDay;
        public int Playthrough;
    }

    [Serializable]
    public class SidePanelDTO
    {
        public int TrustStocks;
        public int MaxTrustStocks;
        public int Sadness;
        public int Joy;
        public int Curiosity;
        public int Fear;
        public int Confusion;
        public int Monitoring;
        public int Trust;
        public int LoopAwareness;
        public int MaxLoopAwareness;
        public string ActBranchInfo;
        public string PassedScenesInfo;
    }

    public enum DialogueType
    {
        Normal,
        Narration,
        SystemMessage
    }

    [Serializable]
    public class DialogueDTO
    {
        public DialogueType Type;
        public string SpeakerName;
        public string Content;
        public string CharacterSpriteKey;
        public string BackgroundSpriteKey;
        public string SpeakerIconKey;
    }

    [Serializable]
    public class ChoiceDTO
    {
        public int ChoiceID;
        public string ChoiceText;
    }

    [Serializable]
    public class DialogueChoiceDTO
    {
        public int ChoiceId;
        public string Title;
        public string Subtitle;
        public string Description;
        public string Condition;
        public bool IsLocked;
        public string ColorType;
    }

    // ==========================================
    // 15종 데이터 구조에 대응하는 DTO 세트 정의
    // ==========================================

    [Serializable]
    public class GlobalProgressDataDTO
    {
        public int playthroughCount;
        public List<string> unlockedEndings;
        public string currentAct;
    }

    [Serializable]
    public class ResourceDataDTO
    {
        public int karma;
        public int emotion;
        public int monitoring;
        public int trust;
        public int playthroughAwareness;
    }

    [Serializable]
    public class SaveDataFileDTO
    {
        public int slotId;
        public GlobalProgressDataDTO globalProgress;
        public Dictionary<string, int> subplotProgress;
        public ResourceDataDTO resources;
        public string currentSceneId;
        public string savedAt;
    }

    [Serializable]
    public class CharacterDTO
    {
        public string id;
        public string name;
        public bool isTalkable;
        public string colorToken;
        public string portraitSpriteKey;
        public List<string> subplotConnections;
    }

    [Serializable]
    public class SceneDTO
    {
        public string id;
        public bool isMain;
        public int expectedMinutes;
        public List<string> characters;
        public string summary;
        public List<string> branchOptions;
    }

    [Serializable]
    public class BranchDTO
    {
        public string id;
        public bool isMainBranch;
        public string endingRequirement;
        public string description;
    }

    [Serializable]
    public class ActOptionDTO
    {
        public string actionType;
        public string requiredSubplotId;
    }

    [Serializable]
    public class InventoryItemDTO
    {
        public string itemId;
        public string name;
        public bool isClue;
        public string description;
        public string connectedSubplotId;
    }

    [Serializable]
    public class GameModuleDTO
    {
        public string moduleId;
        public string name;
        public float averageComplexity;
        public string functionDescription;
    }

    [Serializable]
    public class DialogueLineDTO
    {
        public string dialogueId;
        public string speakerName;
        public string content;
        public string dialogueType;
        public string speakerIconKey;
    }

    [Serializable]
    public class KeyBindDTO
    {
        public string action;
        public string keyName;
    }

    [Serializable]
    public class GameSettingsDTO
    {
        public int resolutionWidth;
        public int resolutionHeight;
        public bool isFullScreen;
        public float masterVolume;
        public float bgmVolume;
        public float sfxVolume;
        public float textSpeed;
        public float autoPlaySpeed;
        public string language;
        public List<KeyBindDTO> keyBinds;
    }

    [Serializable]
    public class AchievementDTO
    {
        public string id;
        public string title;
        public string description;
        public string category;
    }

    [Serializable]
    public class EmotionTrendRowDTO
    {
        public int playthrough;
        public int joy;
        public int fear;
        public int monitoring;
        public int trust;
        public int surprise;
    }

    [Serializable]
    public class PlaythroughLogRowDTO
    {
        public int playthrough;
        public int playTimeSeconds;
        public string endingId;
        public List<string> branchesPassed;
    }

    [Serializable]
    public class BranchMatrixDTO
    {
        public string branchId;
        public string nextSceneId;
        public List<string> endingConditions;
        public List<string> subplotImpacts;
    }

    [Serializable]
    public class SubplotDTO
    {
        public string subplotId;
        public string name;
        public List<string> clueDistribution;
        public string convergedEndingId;
    }

    [Serializable]
    public class LoopVariationDTO
    {
        public int playthroughIndex;
        public float difficultyMultiplier;
        public string narrativeTheme;
        public List<string> loopModifiers;
    }
}
