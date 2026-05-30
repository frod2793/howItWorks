using UnityEngine;
using UnityEngine.UI;
using TMPro;
using System;
using Domain.InGame;

namespace Features.InGame
{
    public class InGameDialogueOptionCardView : MonoBehaviour
    {
        [SerializeField] private TextMeshProUGUI m_titleText;
        [SerializeField] private TextMeshProUGUI m_descriptionText;
        private CanvasGroup m_canvasGroup;
        private Image m_borderImage;
        private Button m_button;

        private DialogueChoiceDTO m_data;
        private Action<int> m_onSelected;

        private void Awake()
        {
            m_borderImage = GetComponent<Image>();
            m_button = GetComponent<Button>();
            m_canvasGroup = GetComponent<CanvasGroup>();
        }

        public void SetCardData(DialogueChoiceDTO dto, Action<int> onSelected)
        {
            m_data = dto;
            m_onSelected = onSelected;

            if (m_titleText != null)
            {
                m_titleText.text = dto.Title;
            }
            if (m_descriptionText != null)
            {
                m_descriptionText.text = dto.Description;
            }

            if (m_borderImage != null)
            {
                if (dto.ColorType == "Yellow")
                {
                    m_borderImage.color = new Color(0.9f, 0.75f, 0.3f, 1f);
                }
                else if (dto.ColorType == "Blue")
                {
                    m_borderImage.color = new Color(0.35f, 0.55f, 0.8f, 1f);
                }
                else if (dto.ColorType == "Orange")
                {
                    m_borderImage.color = new Color(0.9f, 0.5f, 0.4f, 1f);
                }
                else
                {
                    m_borderImage.color = new Color(0.4f, 0.4f, 0.4f, 1f);
                }
            }

            if (m_canvasGroup != null)
            {
                if (dto.IsLocked)
                {
                    m_canvasGroup.alpha = 0.5f;
                }
                else
                {
                    m_canvasGroup.alpha = 1.0f;
                }
            }

            if (m_button != null)
            {
                m_button.interactable = !dto.IsLocked;
            }
        }

        public void func_OnCardClicked()
        {
            if (m_data != null && !m_data.IsLocked && m_onSelected != null)
            {
                m_onSelected.Invoke(m_data.ChoiceId);
            }
        }
    }
}
