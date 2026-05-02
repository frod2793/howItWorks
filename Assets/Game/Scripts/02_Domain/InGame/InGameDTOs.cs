using System;

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

    public class DialogueDTO
    {
        public string SpeakerName;
        public string Content;
        public string CharacterSpriteKey;
        public string BackgroundSpriteKey;
        public string SpeakerIconKey;
    }

    public class ChoiceDTO
    {
        public int ChoiceID;
        public string ChoiceText;
    }
}
