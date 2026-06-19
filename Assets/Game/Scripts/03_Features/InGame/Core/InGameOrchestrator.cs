using System;
using UnityEngine;
using UnityEngine.InputSystem;
using VContainer;
using VContainer.Unity;
using UniTask = Cysharp.Threading.Tasks.UniTask;
using Domain.InGame;

namespace Features.InGame
{
    public class InGameOrchestrator : IInGameOrchestrator, IStartable, ITickable, IDisposable
    {
        [Inject]
        public IDialogueViewModel DialogueVM { get; set; }

        [Inject]
        public IResourceDomainService ResourceService { get; set; }

        [Inject]
        public IGameDataManager GameDataManager { get; set; }

        [Inject]
        public IInGameSaveSystem SaveSystem { get; set; }

        private bool m_isAutoPlay;
        private float m_autoPlayTimer;
        private const float AutoPlayDelay = 2.5f;

        public void Start()
        {
            InitializeGameSession();
        }

        public void InitializeGameSession()
        {
            m_isAutoPlay = false;
            m_autoPlayTimer = 0f;
            
            if (SaveSystem != null)
            {
                SaveSystem.LoadSessionData(1);
            }
        }

        public async UniTask LoadSceneAsync(int sceneNumber)
        {
            if (SaveSystem != null && GameDataManager != null)
            {
                var saveData = GameDataManager.GetSaveData();
                if (saveData != null)
                {
                    SaveSystem.SaveSessionData(saveData);
                }
            }
            await UniTask.Yield();
        }

        public void ProcessNextDialogue()
        {
            if (DialogueVM != null)
            {
                if (DialogueVM.IsTyping)
                {
                    DialogueVM.RequestSkip();
                }
                else
                {
                    DialogueVM.RequestNext();
                }
            }
        }

        public void ToggleAutoPlay()
        {
            m_isAutoPlay = !m_isAutoPlay;
            m_autoPlayTimer = 0f;
        }

        public void ToggleSkip(bool enable)
        {
            if (enable && DialogueVM != null)
            {
                DialogueVM.RequestSkip();
            }
        }

        public void OpenInventory()
        {
            Debug.Log("[InGameOrchestrator] 인벤토리 화면을 활성화합니다.");
        }

        public void OpenBacklog()
        {
            if (DialogueVM != null)
            {
                DialogueVM.RequestBacklog();
            }
        }

        public void Tick()
        {
            if (Keyboard.current == null)
            {
                return;
            }

            if (DialogueVM != null && DialogueVM.IsDisplayingChoices)
            {
                if (Keyboard.current.digit1Key.wasPressedThisFrame)
                {
                    DialogueVM.SelectChoice(1);
                }
                else if (Keyboard.current.digit2Key.wasPressedThisFrame)
                {
                    DialogueVM.SelectChoice(2);
                }
                else if (Keyboard.current.digit3Key.wasPressedThisFrame)
                {
                    DialogueVM.SelectChoice(3);
                }
                else if (Keyboard.current.digit4Key.wasPressedThisFrame)
                {
                    DialogueVM.SelectChoice(4);
                }
                return;
            }

            if (Keyboard.current.spaceKey.wasPressedThisFrame || Keyboard.current.enterKey.wasPressedThisFrame)
            {
                ProcessNextDialogue();
            }

            if (Keyboard.current.ctrlKey.isPressed)
            {
                ToggleSkip(true);
            }

            if (Keyboard.current.aKey.wasPressedThisFrame)
            {
                ToggleAutoPlay();
            }

            if (Keyboard.current.iKey.wasPressedThisFrame)
            {
                OpenInventory();
            }

            if (Keyboard.current.tabKey.wasPressedThisFrame)
            {
                OpenBacklog();
            }

            if (Keyboard.current.ctrlKey.isPressed && Keyboard.current.sKey.wasPressedThisFrame)
            {
                if (SaveSystem != null && GameDataManager != null)
                {
                    var saveData = GameDataManager.GetSaveData();
                    if (saveData != null)
                    {
                        SaveSystem.SaveSessionData(saveData);
                        Debug.Log("[InGameOrchestrator] 퀵 세이브 완료");
                    }
                }
            }

            if (Keyboard.current.ctrlKey.isPressed && Keyboard.current.lKey.wasPressedThisFrame)
            {
                if (SaveSystem != null)
                {
                    var loadedData = SaveSystem.LoadSessionData(1);
                    if (loadedData != null)
                    {
                        Debug.Log("[InGameOrchestrator] 퀵 로드 완료");
                    }
                }
            }

            if (m_isAutoPlay && DialogueVM != null && !DialogueVM.IsTyping && !DialogueVM.IsDisplayingChoices)
            {
                m_autoPlayTimer += Time.deltaTime;
                if (m_autoPlayTimer >= AutoPlayDelay)
                {
                    m_autoPlayTimer = 0f;
                    DialogueVM.RequestNext();
                }
            }
        }

        public void Dispose()
        {
            m_isAutoPlay = false;
        }
    }
}
