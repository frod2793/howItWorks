using VContainer;
using VContainer.Unity;
using Features.InGame;
using UnityEngine;

namespace Features.InGame
{
    public class InGameOrchestrator : IStartable
    {
        private readonly ITopBarViewModel m_topBarVM;
        private readonly IIllustrationViewModel m_illustrationVM;
        private readonly IDialogueViewModel m_dialogueVM;
        private readonly IChoiceViewModel m_choiceVM;
        private readonly IQuickMenuViewModel m_quickMenuVM;
        private readonly IEmotionPopupViewModel m_emotionVM;

        public InGameOrchestrator(
            ITopBarViewModel topBarVM,
            IIllustrationViewModel illustrationVM,
            IDialogueViewModel dialogueVM,
            IChoiceViewModel choiceVM,
            IQuickMenuViewModel quickMenuVM,
            IEmotionPopupViewModel emotionVM)
        {
            m_topBarVM = topBarVM;
            m_illustrationVM = illustrationVM;
            m_dialogueVM = dialogueVM;
            m_choiceVM = choiceVM;
            m_quickMenuVM = quickMenuVM;
            m_emotionVM = emotionVM;

            m_topBarVM.OnMenuClicked += () =>
            {
                m_quickMenuVM.OpenSettings();
            };
        }

        public void Start()
        {
            Debug.Log("[InGameOrchestrator] 시스템 시작");
            InitializeGame();
        }

        private void InitializeGame()
        {
            m_topBarVM.UpdateStats(new Domain.InGame.PlayerStatsDTO
            {
                SceneNumber = 1,
                CurrentLocation = "학교 정문",
                Day = 1,
                Playthrough = 1,
                HP = 100,
                MaxHP = 100,
                Money = 5000
            });

            m_dialogueVM.DisplayDialogue(new Domain.InGame.DialogueDTO
            {
                SpeakerName = "나",
                Content = "드디어 첫날이 시작되었다.",
                BackgroundSpriteKey = "BG_School_Gate"
            });

            m_emotionVM.ShowEmotion("Excited");
        }
    }

    public class InGameLifetimeScope : LifetimeScope
    {
        [Header("뷰 참조")]
        [SerializeField] private InGameTopBarView m_topBarView;
        [SerializeField] private InGameIllustrationView m_illustrationView;
        [SerializeField] private InGameDialogueView m_dialogueView;
        [SerializeField] private InGameChoiceView m_choiceView;
        [SerializeField] private InGameQuickMenuView m_quickMenuView;
        [SerializeField] private InGameEmotionPopupView m_emotionPopupView;
        [SerializeField] private InGameUIVisibilityView m_visibilityView;

        protected override void Configure(IContainerBuilder builder)
        {
            builder.Register<TopBarViewModel>(Lifetime.Singleton).AsImplementedInterfaces();
            builder.Register<IllustrationViewModel>(Lifetime.Singleton).AsImplementedInterfaces();
            builder.Register<DialogueViewModel>(Lifetime.Singleton).AsImplementedInterfaces();
            builder.Register<ChoiceViewModel>(Lifetime.Singleton).AsImplementedInterfaces();
            builder.Register<QuickMenuViewModel>(Lifetime.Singleton).AsImplementedInterfaces();
            builder.Register<EmotionPopupViewModel>(Lifetime.Singleton).AsImplementedInterfaces();
            builder.Register<UIVisibilityViewModel>(Lifetime.Singleton).AsImplementedInterfaces();

            builder.RegisterEntryPoint<InGameOrchestrator>();
            builder.RegisterEntryPoint<InGameInputController>();

            builder.RegisterComponent(m_topBarView);
            builder.RegisterComponent(m_illustrationView);
            builder.RegisterComponent(m_dialogueView);
            builder.RegisterComponent(m_choiceView);
            builder.RegisterComponent(m_quickMenuView);
            builder.RegisterComponent(m_emotionPopupView);
            builder.RegisterComponent(m_visibilityView);
        }
    }
}
