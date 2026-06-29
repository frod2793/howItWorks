using System;
using UnityEngine;
using UnityEngine.UI;
using TMPro;
using VContainer;
using Cysharp.Threading.Tasks;
using System.Threading;
using Domain.InGame;
using DG.Tweening;

namespace Features.InGame
{
    public class InGameDialogueView : MonoBehaviour
    {
        [Header("UI 구성 요소")]
        [SerializeField] private Image m_speakerIcon;
        [SerializeField] private GameObject m_speakerBox;
        [SerializeField] private TextMeshProUGUI m_nameText;
        [SerializeField] private TextMeshProUGUI m_contentText;
        [SerializeField] private TypewriterEffect m_typewriterEffect;
        [SerializeField] private Button m_autoButton;
        [SerializeField] private Button m_inventoryButton;
        [SerializeField] private TextMeshProUGUI m_lineProgressText;

        private Image m_backgroundImage;
        private IDialogueViewModel m_viewModel;
        private CancellationTokenSource m_autoProceedCts;
        private CancellationTokenSource m_dialogueChangeCts;

        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnDialogueUpdated += UpdateDialogue;
            m_viewModel.OnChoicesUpdated += HandleChoicesUpdated;
            m_viewModel.OnAutoPlayChanged += SyncAutoPlayState;

            m_viewModel.OnSkipRequested += () =>
            {
                if (m_typewriterEffect != null)
                {
                    m_typewriterEffect.Skip();
                }
            };

            m_backgroundImage = GetComponent<Image>();

            if (m_backgroundImage != null)
            {
                Color color = m_backgroundImage.color;
                color.a = 0.85f;
                m_backgroundImage.color = color;
            }
        }

        public void func_OnNextButtonClicked()
        {
            if (m_viewModel != null)
            {
                if (m_viewModel.IsFading)
                {
                    return;
                }

                if (m_viewModel.IsTyping)
                {
                    m_viewModel.RequestSkip();
                }
                else
                {
                    m_viewModel.RequestNext();
                }
            }
        }

        public void func_OnAutoButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.IsAutoPlay = !m_viewModel.IsAutoPlay;
            }
        }

        public void func_OnSkipButtonClicked()
        {
        }

        public void func_OnLogButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.RequestBacklog();
            }
        }

        public void func_OnInventoryButtonClicked()
        {
        }

        private async UniTaskVoid StartAutoProceed()
        {
            CancelAutoProceed();
            m_autoProceedCts = new CancellationTokenSource();
            var token = m_autoProceedCts.Token;

            try
            {
                while (m_viewModel != null && m_viewModel.IsAutoPlay)
                {
                    await UniTask.WaitUntil(() => { return !m_viewModel.IsTyping && !m_viewModel.IsDisplayingChoices; }, cancellationToken: token);
                    
                    await UniTask.Delay(System.TimeSpan.FromSeconds(0.5f), cancellationToken: token);

                    if (m_viewModel != null && m_viewModel.IsAutoPlay && !m_viewModel.IsFading && !m_viewModel.IsDisplayingChoices)
                    {
                        m_viewModel.RequestNext();
                        
                        await UniTask.Yield(cancellationToken: token);
                        
                        if (m_viewModel.IsFading)
                        {
                            await UniTask.WaitUntil(() => { return !m_viewModel.IsFading; }, cancellationToken: token);
                        }
                    }
                }
            }
            catch (System.OperationCanceledException)
            {
            }
        }

        private void CancelAutoProceed()
        {
            if (m_autoProceedCts != null)
            {
                m_autoProceedCts.Cancel();
                m_autoProceedCts.Dispose();
                m_autoProceedCts = null;
            }
        }

        private void StartFadeOutEffect()
        {
        }

        private void SyncAutoPlayState(bool isAuto)
        {
            if (m_autoButton != null)
            {
                var image = m_autoButton.GetComponent<Image>();
                if (image != null)
                {
                    if (isAuto)
                    {
                        image.color = new Color(UnityEngine.Random.value, UnityEngine.Random.value, UnityEngine.Random.value, 1f);
                    }
                    else
                    {
                        image.color = Color.white;
                    }
                }
            }

            if (isAuto)
            {
                StartAutoProceed().Forget();
            }
            else
            {
                CancelAutoProceed();
            }
        }



        private void UpdateDialogue(DialogueDTO dialogue)
        {
            if (this == null)
            {
                return;
            }

            if (m_dialogueChangeCts != null)
            {
                m_dialogueChangeCts.Cancel();
                m_dialogueChangeCts.Dispose();
            }
            m_dialogueChangeCts = new CancellationTokenSource();

            PlayDialogueSequenceAsync(dialogue, m_dialogueChangeCts.Token).Forget();
        }

        private async UniTaskVoid PlayDialogueSequenceAsync(DialogueDTO dialogue, CancellationToken token)
        {
            if (m_typewriterEffect != null)
            {
                m_typewriterEffect.Stop();
            }

            if (m_lineProgressText != null)
            {
                m_lineProgressText.text = $"{dialogue.CurrentLine} / {dialogue.TotalLines}";
            }

            if (m_contentText != null && !string.IsNullOrEmpty(m_contentText.text))
            {
                if (m_viewModel != null)
                {
                    m_viewModel.IsFading = true;
                }

                float duration = 0.5f;
                int activeFades = 0;
                var tcs = new UniTaskCompletionSource();

                System.Action onSingleFadeComplete = () =>
                {
                    activeFades--;
                    if (activeFades <= 0)
                    {
                        tcs.TrySetResult();
                    }
                };

                if (m_contentText != null)
                {
                    activeFades++;
                    m_contentText.DOFade(0f, duration)
                        .SetLink(m_contentText.gameObject)
                        .OnComplete(() => { onSingleFadeComplete(); });
                }

                if (m_nameText != null && m_speakerBox != null && m_speakerBox.activeSelf)
                {
                    activeFades++;
                    m_nameText.DOFade(0f, duration)
                        .SetLink(m_nameText.gameObject)
                        .OnComplete(() => { onSingleFadeComplete(); });
                }

                if (activeFades == 0)
                {
                    tcs.TrySetResult();
                }

                try
                {
                    await tcs.Task.AttachExternalCancellation(token);
                }
                catch (OperationCanceledException)
                {
                    return;
                }

                if (m_viewModel != null)
                {
                    m_viewModel.IsFading = false;
                }
            }

            if (m_contentText != null)
            {
                m_contentText.DOKill();
                m_contentText.text = "";
                Color c = m_contentText.color;
                c.a = 1f;
                m_contentText.color = c;
            }
            if (m_nameText != null)
            {
                m_nameText.DOKill();
                Color c = m_nameText.color;
                c.a = 1f;
                m_nameText.color = c;
            }

            if (dialogue.Type == DialogueType.Narration)
            {
                if (m_speakerBox != null)
                {
                    m_speakerBox.SetActive(false);
                }
                if (m_speakerIcon != null)
                {
                    m_speakerIcon.gameObject.SetActive(false);
                }
                if (m_viewModel != null)
                {
                    m_viewModel.IsTyping = true;
                }
                if (m_typewriterEffect != null && m_contentText != null)
                {
                    try
                    {
                        await m_typewriterEffect.Play(m_contentText, dialogue.Content, () => 
                        { 
                            if (m_viewModel != null)
                            {
                                m_viewModel.IsTyping = false; 
                            }
                        }).AttachExternalCancellation(token);
                    }
                    catch (OperationCanceledException)
                    {
                        return;
                    }
                }
                else if (m_contentText != null)
                {
                    m_contentText.text = dialogue.Content;
                    if (m_viewModel != null)
                    {
                        m_viewModel.IsTyping = false;
                    }
                }
            }
            else if (dialogue.Type == DialogueType.SystemMessage)
            {
                if (m_speakerBox != null)
                {
                    m_speakerBox.SetActive(false);
                }
                if (m_speakerIcon != null)
                {
                    m_speakerIcon.gameObject.SetActive(false);
                }
                if (m_contentText != null)
                {
                    m_contentText.text = dialogue.Content;
                    if (m_viewModel != null)
                    {
                        m_viewModel.IsTyping = false;
                    }
                }
            }
            else
            {
                if (m_speakerBox != null)
                {
                    m_speakerBox.SetActive(true);
                }
                if (m_nameText != null)
                {
                    m_nameText.text = dialogue.SpeakerName;
                }
                if (m_speakerIcon != null)
                {
                    if (string.IsNullOrEmpty(dialogue.SpeakerIconKey))
                    {
                        m_speakerIcon.gameObject.SetActive(false);
                    }
                    else
                    {
                        m_speakerIcon.gameObject.SetActive(true);
                    }
                }
                if (m_viewModel != null)
                {
                    m_viewModel.IsTyping = true;
                }
                if (m_typewriterEffect != null && m_contentText != null)
                {
                    try
                    {
                        await m_typewriterEffect.Play(m_contentText, dialogue.Content, () => 
                        { 
                            if (m_viewModel != null)
                            {
                                m_viewModel.IsTyping = false; 
                            }
                        }).AttachExternalCancellation(token);
                    }
                    catch (OperationCanceledException)
                    {
                        return;
                    }
                }
                else if (m_contentText != null)
                {
                    m_contentText.text = dialogue.Content;
                    if (m_viewModel != null)
                    {
                        m_viewModel.IsTyping = false;
                    }
                }
            }
        }

        private void HandleChoicesUpdated(System.Collections.Generic.List<DialogueChoiceDTO> choices)
        {
            if (this == null)
            {
                return;
            }

            if (choices != null && choices.Count > 0)
            {
                gameObject.SetActive(false);
            }
            else
            {
                gameObject.SetActive(true);
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnDialogueUpdated -= UpdateDialogue;
                m_viewModel.OnChoicesUpdated -= HandleChoicesUpdated;
                m_viewModel.OnAutoPlayChanged -= SyncAutoPlayState;
            }
            if (m_dialogueChangeCts != null)
            {
                m_dialogueChangeCts.Cancel();
                m_dialogueChangeCts.Dispose();
            }
            CancelAutoProceed();
        }
    }
}
