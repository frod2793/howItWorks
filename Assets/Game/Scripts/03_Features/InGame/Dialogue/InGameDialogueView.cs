using UnityEngine;
using UnityEngine.UI;
using TMPro;
using VContainer;
using Cysharp.Threading.Tasks;
using Domain.InGame;

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

        private Image m_backgroundImage;
        private IDialogueViewModel m_viewModel;
        private IQuickMenuViewModel m_quickMenuVM;

        [Inject]
        public void Construct(IDialogueViewModel viewModel, IQuickMenuViewModel quickMenuVM)
        {
            m_viewModel = viewModel;
            m_quickMenuVM = quickMenuVM;
            m_viewModel.OnDialogueUpdated += UpdateDialogue;

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
                m_viewModel.RequestNext();
            }
        }

        public void func_OnAutoButtonClicked()
        {
            if (m_quickMenuVM != null)
            {
                m_quickMenuVM.ClickAuto();
            }
        }

        public void func_OnSkipButtonClicked()
        {
            if (m_quickMenuVM != null)
            {
                m_quickMenuVM.ClickSkip();
            }
        }

        public void func_OnLogButtonClicked()
        {
            if (m_quickMenuVM != null)
            {
                m_quickMenuVM.RequestLog();
            }
        }

        public void func_OnMenuButtonClicked()
        {
            if (m_quickMenuVM != null)
            {
                m_quickMenuVM.RequestMenu();
            }
        }

        private void UpdateDialogue(DialogueDTO dialogue)
        {
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
                if (m_typewriterEffect != null && m_contentText != null)
                {
                    m_typewriterEffect.Play(m_contentText, dialogue.Content).Forget();
                }
                else if (m_contentText != null)
                {
                    m_contentText.text = dialogue.Content;
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
                    if (m_typewriterEffect != null)
                    {
                        m_typewriterEffect.Stop();
                    }
                    m_contentText.text = $"<mspace=16px>{dialogue.Content}</mspace>";
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
                if (m_typewriterEffect != null && m_contentText != null)
                {
                    m_typewriterEffect.Play(m_contentText, dialogue.Content).Forget();
                }
                else if (m_contentText != null)
                {
                    m_contentText.text = dialogue.Content;
                }
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnDialogueUpdated -= UpdateDialogue;
            }
        }
    }
}
